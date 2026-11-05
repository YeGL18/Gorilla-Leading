package com.gorilla.leading;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.provider.Settings;
import android.widget.Toast;
import androidx.core.content.FileProvider;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HashSet;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Direct-APK trial updates. Never installs silently; Android owns confirmation. */
final class AppUpdates {
    private final Activity activity;
    private final Api api;
    private final ExecutorService io=Executors.newSingleThreadExecutor();
    private boolean active=false,waitingPermission=false;
    private volatile boolean closed=false;
    private File pending;
    AppUpdates(Activity activity,Api api){this.activity=activity;this.api=api;}

    void check(boolean manual){
        if(active||closed)return;
        if(!api.session.baseUrl().startsWith("https://")){
            if(manual)message("請先設定並驗證連線服務網址。");return;
        }
        if(manual)Toast.makeText(activity,"正在檢查更新…",Toast.LENGTH_SHORT).show();
        active=true;
        io.submit(()->{
            try {
                final String base=api.session.baseUrl();
                JSONObject release=api.call("GET","android/update",null,false);
                run(()->{
                    active=false;
                    if(!base.equals(api.session.baseUrl()))return;
                    if(!release.optBoolean("available")||release.optLong("versionCode")<=BuildConfig.VERSION_CODE){
                        if(manual)message(release.optBoolean("available")?"目前已是最新版本。":"服務尚未發佈 Android 更新。");return;
                    }
                    Ui.showDialog(new AlertDialog.Builder(activity).setTitle("有新版本 "+release.optString("versionName"))
                        .setMessage("下載後會核對安裝包及簽章，並由 Android 要求你確認安裝。")
                        .setNegativeButton("稍後",null).setPositiveButton("下載更新",(d,w)->download(base,release)),false);
                });
            }catch(Exception error){run(()->{active=false;if(manual)message("未能檢查更新，登入及車牌資料不受影響。請檢查服務連線。");});}
        });
    }

    private void download(String base,JSONObject release){
        if(active||closed)return;
        if(!BuildConfig.DEBUG){message("此版本請透過原有應用程式商店更新。");return;}
        active=true;Toast.makeText(activity,"正在下載更新…",Toast.LENGTH_LONG).show();
        io.submit(()->{
            File file=new File(new File(activity.getCacheDir(),"updates"),"update.apk");
            try {
                long bytes=release.getLong("bytes"),version=release.getLong("versionCode");
                String expected=release.getString("sha256");
                if(bytes<1||bytes>200L*1024*1024||!expected.matches("[a-fA-F0-9]{64}"))throw new Exception("更新資料格式不正確");
                if(!file.getParentFile().isDirectory()&&!file.getParentFile().mkdirs())throw new Exception("無法建立下載目錄");
                HttpURLConnection connection=(HttpURLConnection)new URL(base+"/android/apk").openConnection();
                connection.setInstanceFollowRedirects(false);connection.setConnectTimeout(15000);connection.setReadTimeout(30000);connection.setUseCaches(false);
                MessageDigest digest=MessageDigest.getInstance("SHA-256");long total=0;
                try {
                    if(connection.getResponseCode()!=200)throw new Exception("下載服務暫時無法使用");
                    try(InputStream input=connection.getInputStream();FileOutputStream output=new FileOutputStream(file)){
                        byte[] buffer=new byte[65536];int count;
                        while((count=input.read(buffer))!=-1){
                            if(closed||Thread.currentThread().isInterrupted())throw new Exception("下載已取消");
                            total+=count;if(total>bytes)throw new Exception("安裝包大小不符");digest.update(buffer,0,count);output.write(buffer,0,count);
                        }
                    }
                }finally{connection.disconnect();}
                if(total!=bytes||!expected.equalsIgnoreCase(hex(digest.digest())))throw new Exception("安裝包完整性檢查失敗，請重新下載");
                verifyPackage(file,version);
                run(()->{active=false;pending=file;install();});
            }catch(Exception error){file.delete();run(()->{active=false;message(error.getMessage()==null?"下載更新失敗":error.getMessage());});}
        });
    }

    private void verifyPackage(File file,long expected) throws Exception {
        PackageManager manager=activity.getPackageManager();
        PackageInfo installed=manager.getPackageInfo(activity.getPackageName(),PackageManager.GET_SIGNING_CERTIFICATES);
        PackageInfo archive=manager.getPackageArchiveInfo(file.getAbsolutePath(),PackageManager.GET_SIGNING_CERTIFICATES);
        checkPackage(installed,archive,activity.getPackageName(),expected);
    }
    static void checkPackage(PackageInfo installed,PackageInfo archive,String expectedPackage,long expected) throws Exception {
        if(archive==null||!expectedPackage.equals(archive.packageName)||archive.getLongVersionCode()!=expected||expected<=installed.getLongVersionCode())
            throw new Exception("安裝包的應用程式或版本不符");
        if(archive.signingInfo==null||installed.signingInfo==null||!new HashSet<Signature>(Arrays.asList(installed.signingInfo.getApkContentsSigners()))
            .equals(new HashSet<Signature>(Arrays.asList(archive.signingInfo.getApkContentsSigners()))))
            throw new Exception("安裝包簽章不符，已取消更新");
    }

    private void install(){
        if(pending==null||closed)return;
        if(!activity.getPackageManager().canRequestPackageInstalls()){
            waitingPermission=true;
            Ui.showDialog(new AlertDialog.Builder(activity).setTitle("允許安裝更新")
                .setMessage("Android 需要你允許 Gorilla 安裝此來源的更新。你可以隨時取消。")
                .setNegativeButton("取消",(d,w)->waitingPermission=false)
                .setPositiveButton("開啟設定",(d,w)->{
                    try{activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+activity.getPackageName())));}
                    catch(Exception e){waitingPermission=false;message("未能開啟安裝權限設定。");}
                }),false);return;
        }
        try {
            Uri uri=FileProvider.getUriForFile(activity,activity.getPackageName()+".updates",pending);
            Intent intent=new Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            waitingPermission=false;activity.startActivity(intent);
        }catch(Exception e){message("未能開啟 Android 安裝程式，請稍後再試。");}
    }
    void resumed(){if(waitingPermission){waitingPermission=false;if(activity.getPackageManager().canRequestPackageInstalls())install();}}
    void close(){closed=true;io.shutdownNow();}
    private void run(Runnable block){activity.runOnUiThread(()->{if(!closed&&!activity.isFinishing()&&!activity.isDestroyed())block.run();});}
    private void message(String text){Ui.showDialog(new AlertDialog.Builder(activity).setTitle("應用程式更新").setMessage(text).setPositiveButton("知道了",null),false);}
    private static String hex(byte[] bytes){StringBuilder value=new StringBuilder();for(byte b:bytes)value.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return value.toString();}
}
