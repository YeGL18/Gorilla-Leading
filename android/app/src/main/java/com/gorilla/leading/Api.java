package com.gorilla.leading;

import android.content.Context;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URI;
import java.nio.charset.StandardCharsets;

final class Api {
    final Session session;
    Api(Context context) { session = new Session(context); }
    static JSONObject data(Object... pairs) throws Exception {
        JSONObject result=new JSONObject(); for(int i=0;i<pairs.length;i+=2) result.put((String)pairs[i],pairs[i+1]); return result;
    }
    JSONObject call(String method,String path,JSONObject body,boolean authenticated) throws Exception {
        return callAt(session.baseUrl(),method,path,body,authenticated);
    }
    static String normalizedBase(String value) throws Exception {
        URI uri=new URI(value.trim());
        if(!"https".equalsIgnoreCase(uri.getScheme())||uri.getHost()==null||uri.getUserInfo()!=null||uri.getQuery()!=null||uri.getFragment()!=null)
            throw new Exception("請輸入有效的 HTTPS 服務網址");
        String path=uri.getPath()==null?"":uri.getPath().replaceAll("/+$", "");
        if(path.isEmpty())path="/v1/parking-community";
        if(!path.equals("/v1/parking-community"))throw new Exception("網址路徑應為 /v1/parking-community");
        return new URI("https",null,uri.getHost(),uri.getPort(),path,null,null).toASCIIString();
    }
    String validateServer(String value) throws Exception {
        String base=normalizedBase(value);
        JSONObject result=callAt(base,"GET","capabilities",null,false);
        if(!"gorilla-parking-community".equals(result.optString("service"))||result.optInt("apiVersion")!=1)
            throw new Exception("此網址不是相容的 Gorilla 服務；請更新 Windows 後端或檢查網址");
        return base;
    }
    private JSONObject callAt(String base,String method,String path,JSONObject body,boolean authenticated) throws Exception {
        if (!base.startsWith("https://")) throw new Exception("測試服務未設定");
        HttpURLConnection connection=(HttpURLConnection)new URL(base+"/"+path).openConnection();
        connection.setRequestMethod(method); connection.setConnectTimeout(15000);connection.setReadTimeout(20000);
        connection.setInstanceFollowRedirects(false); connection.setUseCaches(false);
        connection.setRequestProperty("Content-Type","application/json");
        if(authenticated) {
            String token=session.tokenFor(base); if(token.isEmpty()) throw new Exception("請先登入");
            connection.setRequestProperty("Authorization","Bearer "+token);
        }
        try {
            if(body!=null) { connection.setDoOutput(true);try(java.io.OutputStream output=connection.getOutputStream()){output.write(body.toString().getBytes(StandardCharsets.UTF_8));} }
            int status=connection.getResponseCode();
            InputStream stream=status<400?connection.getInputStream():connection.getErrorStream();
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();
            if(stream!=null) try(InputStream input=stream) { byte[] buffer=new byte[4096];int count;while((count=input.read(buffer))!=-1){bytes.write(buffer,0,count);if(bytes.size()>2000000)throw new Exception("回應內容過大");} }
            JSONObject result=new JSONObject(bytes.toString("UTF-8"));
            if(status>=400) {
                // Keep credentials during outages, proxy errors and reauthentication.
                throw new Exception(error(result.optString("error")));
            }
            return result;
        } finally { connection.disconnect(); }
    }
    static String error(String code) {
        switch(code) {
            case "recipient_unavailable":return "此車牌沒有可接收提醒的用戶";
            case "invalid_or_expired_code":return "驗證碼錯誤或已過期";
            case "rate_limited":return "操作太頻密，請稍後再試";
            case "thread_unavailable":return "對話已過期或無法存取";
            case "sign_in_required":return "登入憑證已失效，請重新登入；本機資料仍保留";
            case "email_unavailable":return "驗證電郵暫時無法寄出";
            case "not_found":return "服務不支援此操作，請先更新 Windows 後端";
            default:return "操作未完成，請檢查輸入或稍後再試";
        }
    }
}
