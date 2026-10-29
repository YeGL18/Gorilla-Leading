package com.gorilla.leading;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.*;
import android.text.InputFilter;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

public class MainActivity extends Activity {
    private Api api; private LinearLayout body;private TextView notice;private final ExecutorService io=Executors.newSingleThreadExecutor();
    private String screen="home", threadId="", plate="";private JSONArray currentMessages=new JSONArray();
    private String lastSendPayload="";
    private String sendKey=UUID.randomUUID().toString(),sendText="留意入返咪錶";private boolean busy=false;private int generation=0;
    interface Work {JSONObject run() throws Exception;}
    interface Done {void accept(JSONObject result) throws Exception;}
    @Override public void onCreate(Bundle state){super.onCreate(state);api=new Api(this);PushService.channel(this);PushService.register(this);home();openNotification(getIntent());}
    @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);openNotification(intent);}
    private void openNotification(Intent intent){String id=intent.getStringExtra("threadId");if(id!=null&&!api.session.token().isEmpty()){threadId=id;plate="提醒對話";conversation();}}
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private void page(String title,String name){
        screen=name;busy=false;generation++;
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(Color.rgb(247,245,240));
        root.setPadding(dp(20),dp(24),dp(20),dp(16));
        root.setOnApplyWindowInsetsListener((v,insets)->{root.setPadding(dp(20),insets.getSystemWindowInsetTop()+dp(12),dp(20),insets.getSystemWindowInsetBottom()+dp(12));return insets;});
        TextView brand=new TextView(this);brand.setText("GORILLA LEADING  /  泊車互助");brand.setTextSize(12);brand.setTextColor(Color.rgb(147,106,23));root.addView(brand);
        TextView heading=new TextView(this);heading.setText(title);heading.setTextSize(27);heading.setTypeface(null,Typeface.BOLD);heading.setPadding(0,dp(12),0,dp(12));root.addView(heading);
        ScrollView scroll=new ScrollView(this);body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);scroll.addView(body);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        notice=new TextView(this);notice.setTextSize(13);notice.setPadding(0,dp(10),0,dp(8));root.addView(notice);
        if(!name.equals("home")){Button back=new Button(this);back.setText("返回主頁");back.setOnClickListener(v->home());root.addView(back);}
        setContentView(root);
    }
    private void text(String value){TextView v=new TextView(this);v.setText(value);v.setTextSize(16);v.setPadding(0,dp(8),0,dp(8));body.addView(v);}
    private Button button(String label,Runnable action){Button v=new Button(this);v.setText(label);v.setAllCaps(false);body.addView(v,new LinearLayout.LayoutParams(-1,dp(54)));v.setOnClickListener(w->{if(!busy)action.run();});return v;}
    private EditText field(String hint,int input){EditText value=new EditText(this);value.setHint(hint);value.setSingleLine(true);value.setInputType(input);body.addView(value);return value;}
    private void task(Work work,Done done){
        if(busy)return;busy=true;notice.setText("處理中…");int origin=generation;
        io.submit(()->{try{JSONObject result=work.run();runOnUiThread(()->{if(isFinishing()||origin!=generation)return;busy=false;notice.setText("");try{done.accept(result);}catch(Exception e){notice.setText("未能顯示回應，請重新整理");}});}
        catch(Exception e){runOnUiThread(()->{if(origin!=generation)return;busy=false;notice.setText(e.getMessage()==null?"連線失敗，請重試":e.getMessage());});}});
    }
    private void home(){
        page("掃牌、一撳，提醒車主","home");
        text("核心功能免費。無需綁定自己的車牌，亦可提醒其他車主。");
        button("開相機掃車牌",()->{if(!api.session.onboarded()){onboarding();return;}startActivityForResult(new Intent(this,ScannerActivity.class),10);});
        button("手動輸入車牌",()->plateEntry(false));
        button("提醒對話",this::inbox);button("我的車牌與帳號",this::settings);
        text("只提供互助提醒，不提供咪錶繳費、代繳或罰單資訊認證。");
        if(!BuildConfig.FIREBASE_CONFIGURED)text("本 APK 尚未設定 Firebase，遠端推送未啟用；可以手動重新整理對話。");
    }
    private void onboarding(){page("先設定自己的車牌？","onboarding");text("同一車牌可以多人綁定，共同接收提醒。亦可略過，先幫其他人發提醒。");button("設定車牌",()->{api.session.onboard();plateEntry(true);});button("略過，開始掃描",()->{api.session.onboard();startActivityForResult(new Intent(this,ScannerActivity.class),10);});}
    private void login(){login(this::settings);}
    private void login(Runnable afterLogin){
        page("電郵登入／註冊","login");EditText email=field("電郵地址",33);EditText code=field("6 位驗證碼",2);code.setFilters(new InputFilter[]{new InputFilter.LengthFilter(6)});
        text("以電郵驗證身分，無需先綁定車牌。驗證碼 10 分鐘內有效。");
        button("取得驗證碼",()->task(()->api.call("POST","auth/start",Api.data("email",email.getText().toString().trim().toLowerCase(Locale.ROOT)),false),r->notice.setText("驗證碼已寄出，請檢查收件匣／垃圾郵件；重新寄出需等 60 秒。")));
        button("登入",()->task(()->api.call("POST","auth/verify",Api.data("email",email.getText().toString().trim().toLowerCase(Locale.ROOT),"code",code.getText().toString().trim()),false),r->{api.session.save(r.getString("token"));PushService.register(this);afterLogin.run();}));
    }
    private boolean requireLogin(){if(api.session.token().isEmpty()){login(screen.equals("composer")?this::composer:this::settings);return false;}return true;}
    private void settings(){
        page("我的車牌與帳號","settings");
        text("只有自己或獲授權駕駛的車輛先綁定；這項聲明不等於平台核實車主身分。");
        if(api.session.token().isEmpty()){button("登入／註冊",this::login);return;}
        button("新增車牌",()->plateEntry(true));
        button("開啟手機通知",()->{
            if(!BuildConfig.FIREBASE_CONFIGURED){notice.setText("此 APK 未加入 Firebase 設定，遠端推送暫未啟用。");return;}
            if(Build.VERSION.SDK_INT>=33)requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},20);
            PushService.register(this);
            task(()->api.call("GET","capabilities",null,false),r->notice.setText(r.getJSONObject("push").optBoolean("fcm")?"已嘗試登記推送，請允許手機通知；實際接收仍受網絡及系統設定影響。":"後端等待 Firebase 私鑰設定，請先手動整理對話。"));
        });
        button("登出",()->task(()->{api.call("DELETE","me/devices/"+api.session.deviceId(),null,true);return api.call("POST","auth/logout",null,true);},r->{api.session.clear();PushService.cancelAll(this);home();}));
        button("刪除帳號及資料",()->new AlertDialog.Builder(this).setTitle("永久刪除帳號？").setMessage("將刪除車牌綁定、登入及相關訊息，無法復原。").setNegativeButton("取消",null).setPositiveButton("刪除",(d,w)->task(()->api.call("DELETE","me",null,true),r->{api.session.clear();PushService.cancelAll(this);home();})).show());
        task(()->api.call("GET","me/plates",null,true),r->{JSONArray rows=r.getJSONArray("plates");for(int i=0;i<rows.length();i++){String p=rows.getJSONObject(i).getString("plate");button("已綁定："+p+"　解除",()->new AlertDialog.Builder(this).setTitle("解除 "+p+"？").setMessage("不會影響其他綁定者，你將失去收到的舊對話存取權。").setNegativeButton("取消",null).setPositiveButton("解除",(d,w)->task(()->api.call("DELETE","me/plates/"+Plate.canonical(p),null,true),v->settings())).show());}});
        text("對話建立後 7 日自動刪除。禁止騷擾、起底及爭執。墊款／還錢屬雙方自願安排，平台不處理金錢糾紛。");
    }
    private void plateEntry(boolean own){
        if(own&&api.session.token().isEmpty()){login(()->plateEntry(true));return;}
        page(own?"綁定我的車牌":"輸入對方車牌","plate");
        EditText value=field("車牌（最多 8 字元）",1);value.setShowSoftInputOnFocus(false);value.setKeyListener(null);value.setLongClickable(false);value.setTypeface(Typeface.MONOSPACE);value.setTextSize(28);
        String[] rows={"1234567890","ABCDEFGH","JKLMNPRS","TUVWXYZ"};
        for(String row:rows){LinearLayout keys=new LinearLayout(this);for(char c:row.toCharArray()){Button key=new Button(this);key.setMinWidth(0);key.setMinimumWidth(0);key.setPadding(0,0,0,0);key.setText(String.valueOf(c));keys.addView(key,new LinearLayout.LayoutParams(0,dp(48),1));key.setOnClickListener(v->{if(value.length()<8)value.setText(value.getText().toString()+c);});}body.addView(keys);}
        button("空格",()->{if(value.length()>0&&value.length()<8&&!value.getText().toString().endsWith(" "))value.append(" ");});
        button("刪除上一個字元",()->{String p=value.getText().toString();if(!p.isEmpty())value.setText(p.substring(0,p.length()-1));});
        CheckBox consent=new CheckBox(this);consent.setText("我確認是車主或獲授權駕駛者，同意用車牌接收提醒。");if(own)body.addView(consent);
        button(own?"綁定車牌":"確認車牌",()->{String p=value.getText().toString().trim();if(!Plate.valid(p)){notice.setText("請輸入有效車牌");return;}String normal=Plate.standard(p);if(normal!=null)p=normal;final String target=p;
            if(own){if(!consent.isChecked()){notice.setText("請先確認授權聲明");return;}if(!requireLogin())return;task(()->api.call("POST","me/plates",Api.data("plate",target,"authorisedDriver",true),true),r->settings());}
            else{plate=target;sendText="留意入返咪錶";sendKey=UUID.randomUUID().toString();composer();}});
    }
    private void composer(){
        page("提醒 "+plate,"composer");text("請再次核對車牌；所有綁定者共用同一條對話。");
        for(String t:new String[]{"小心違例泊車","留意入返咪錶","我幫你墊錢入咗咪錶"})button(t,()->{sendText=t;sendKey=UUID.randomUUID().toString();notice.setText("已選："+t);});
        EditText custom=field("自由輸入文字（最多 200 字）",1);custom.setFilters(new InputFilter[]{new InputFilter.LengthFilter(200)});
        text("「我幫你墊錢入咗咪錶」只是發送者的聲明，平台不核實付款，亦不參與咪錶繳費。");
        button("發送提醒",()->{String message=custom.getText().toString().trim();if(message.isEmpty())message=sendText;sendText=message;if(!requireLogin())return;final String outgoing=message; final String targetPlate=plate;
            String payload=targetPlate+"\n"+outgoing;if(!payload.equals(lastSendPayload)){sendKey=UUID.randomUUID().toString();lastSendPayload=payload;}final String requestKey=sendKey;
            task(()->api.call("POST","threads",Api.data("plate",targetPlate,"text",outgoing,"idempotencyKey",requestKey),true),r->{threadId=r.getString("threadId");conversation();});});
    }
    private void inbox(){
        if(api.session.token().isEmpty()){login(this::inbox);return;}page("提醒對話","inbox");button("重新整理",this::inbox);
        task(()->api.call("GET","threads",null,true),r->{JSONArray rows=r.getJSONArray("threads");if(rows.length()==0)text("暫時沒有提醒");for(int i=0;i<rows.length();i++){JSONObject row=rows.getJSONObject(i);JSONObject last=row.optJSONObject("lastMessage");button(row.getString("plate")+"\n"+(last==null?"提醒對話":last.optString("text")),()->{threadId=row.optString("id");plate=row.optString("plate");conversation();});}});
    }
    private void conversation(){
        if(api.session.token().isEmpty()){login(this::conversation);return;}page(plate,"conversation");button("重新整理",this::conversation);
        EditText reply=field("回覆（最多 200 字）",1);reply.setFilters(new InputFilter[]{new InputFilter.LengthFilter(200)});
        for(String t:new String[]{"感謝師兄","唔該","多謝提醒"})button(t,()->reply.setText(t));
        final String targetThread=threadId; final String[] previous={""}, requestKey={UUID.randomUUID().toString()};
        button("回覆",()->{String value=reply.getText().toString().trim();if(value.isEmpty())return;if(!value.equals(previous[0])){previous[0]=value;requestKey[0]=UUID.randomUUID().toString();}final String key=requestKey[0];task(()->api.call("POST","threads/"+targetThread+"/messages",Api.data("text",value,"idempotencyKey",key),true),r->conversation());});
        button("舉報不當訊息",()->task(()->api.call("POST","threads/"+targetThread+"/reports",Api.data("reason","用戶舉報不當訊息"),true),r->notice.setText("舉報已記錄，等待處理")));
        text("建立後 7 日到期，回覆不會延長期限。長按訊息可封鎖發送者。");
        task(()->api.call("GET","threads/"+targetThread+"/messages",null,true),r->{currentMessages=r.getJSONArray("messages");for(int i=0;i<currentMessages.length();i++){JSONObject msg=currentMessages.getJSONObject(i);TextView v=new TextView(this);v.setText(msg.getString("text"));v.setTextSize(17);v.setPadding(dp(12),dp(16),dp(12),dp(16));v.setBackgroundColor(Color.WHITE);body.addView(v);v.setOnLongClickListener(w->{new AlertDialog.Builder(this).setTitle("封鎖此發送者？").setNegativeButton("取消",null).setPositiveButton("封鎖",(d,n)->task(()->api.call("POST","blocks",Api.data("userId",msg.optString("authorId")),true),result->inbox())).show();return true;});}});
    }
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==10&&result==RESULT_OK&&data!=null){plate=data.getStringExtra("plate");sendText="留意入返咪錶";sendKey=UUID.randomUUID().toString();composer();}}
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] grants){super.onRequestPermissionsResult(request,permissions,grants);if(request==20)PushService.register(this);}
    @Override protected void onResume(){super.onResume();if(api!=null)PushService.register(this);}
    @Override public void onBackPressed(){home();}
}
