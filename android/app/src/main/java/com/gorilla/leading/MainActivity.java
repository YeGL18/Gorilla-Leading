package com.gorilla.leading;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.os.*;
import android.text.InputFilter;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.text.Editable;
import android.view.*;
import android.widget.*;
import androidx.activity.*;
import androidx.annotation.NonNull;
import androidx.core.view.*;
import com.qmdeve.liquidglass.widget.LiquidGlassView;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

public class MainActivity extends ComponentActivity {
    private Api api; private FrameLayout root,capture; private PageHost pages;
    private LinearLayout content,body,footer,messagesPanel,headerActions;
    private ScrollView scroll; private FrameLayout tabBar; private View tabPill;
    private EditText replyInput;private Button replySend;private final List<Button> replyTemplates=new ArrayList<>();
    private boolean resumed=false,polling=false;private String lastInboxJSON="",lastThreadJSON="";
    private final Handler live=new Handler(Looper.getMainLooper());
    private final Runnable poll=new Runnable(){public void run(){refreshVisibleConversation();if(resumed)live.postDelayed(this,5000);}};
    private TextView notice;private final ExecutorService io=Executors.newSingleThreadExecutor();
    private String screen="home", threadId="", plate="";private JSONArray currentMessages=new JSONArray();
    private String tabFocus="home";
    private OrbBackground orbs;
    private AppUpdates updates;
    private final ArrayDeque<ScreenState> history=new ArrayDeque<>();
    private final Map<String,ScreenState> tabPages=new HashMap<>();
    private final Map<String,ReplyDraft> replyDrafts=new HashMap<>();
    private final List<ImageView> tabIcons=new ArrayList<>();
    private final List<TextView> tabLabels=new ArrayList<>();
    private View previousPage;
    private boolean backPreview=false,transitioning=false,previewMode=false,tabGlassActive=false;
    private int backEdge=0,systemTop=0,systemBottom=0,systemLeft=0,systemRight=0,keyboardBottom=0;
    private String displayedTab="home";

    private final class ScreenState {
        String name=screen, focus=displayedTab, thread=threadId, recipient=plate;
        LinearLayout page=content, list=body, bottom=footer, messages=messagesPanel, actions=headerActions;
        ScrollView scroller=scroll;
        TextView status=notice;
        EditText editor=replyInput;
        Button send=replySend;
        List<Button> templates=new ArrayList<>(replyTemplates);
        String inboxJSON=lastInboxJSON, threadJSON=lastThreadJSON;
        JSONArray records=currentMessages;
    }
    private String lastSendPayload="";
    private String sendKey=UUID.randomUUID().toString(),sendText="留意入返咪錶";private boolean busy=false;private int generation=0;
    interface Work {JSONObject run() throws Exception;}
    interface Done {void accept(JSONObject result) throws Exception;}

    /** 預測性返回：主頁放手俾系統（退回首頁），其他頁做縮放預覽。 */
    private final OnBackPressedCallback back=new OnBackPressedCallback(false){
        @Override public void handleOnBackStarted(@NonNull BackEventCompat event){content.animate().cancel();finishBackPreview();prepareBack(event.getSwipeEdge());}
        @Override public void handleOnBackPressed(){navigateBack();}
        @Override public void handleOnBackProgressed(@NonNull BackEventCompat event){
            if(content==null||transitioning)return;
            if(!backPreview)prepareBack(event.getSwipeEdge());
            float p=event.getProgress();
            content.setScaleX(1f-.06f*p);content.setScaleY(1f-.06f*p);
            content.setTranslationX((backEdge==0?1:-1)*p*dp(68));pages.invalidate();
        }
        @Override public void handleOnBackCancelled(){
            cancelBack();
        }
    };

    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        EdgeToEdge.enable(this);
        {WindowManager.LayoutParams w=getWindow().getAttributes();w.layoutInDisplayCutoutMode=WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;getWindow().setAttributes(w);}
        getWindow().setNavigationBarContrastEnforced(false);
        api=new Api(this);getOnBackPressedDispatcher().addCallback(this,back);
        orbs=new OrbBackground(getResources().getDisplayMetrics().density);
        createShell();
        updates=new AppUpdates(this,api);updates.check(false);
        if(!api.session.token().isEmpty()&&api.session.userId().isEmpty()){
            String origin=api.session.baseUrl();
            io.submit(()->{try{String id=api.call("GET","me/session",null,true).optString("userId");runOnUiThread(()->{if(origin.equals(api.session.baseUrl()))api.session.saveIdentity(id);});}catch(Exception ignored){}});
        }
        PushService.channel(this);PushService.register(this);
        home();openNotification(getIntent());
    }
    @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);openNotification(intent);}
    private void openNotification(Intent intent){String id=intent.getStringExtra("threadId");if(id!=null&&!api.session.token().isEmpty()){inbox();threadId=id;plate="提醒對話";conversation();}}
    private void navigateBack(){
        if(transitioning)return;
        ScreenState target=history.peek();
        if(target==null)target=tabPages.get("home");
        if(target==null||target.page==content){home();return;}
        final ScreenState destination=target;
        if(backPreview){
            transitioning=true;
            content.animate().translationX((backEdge==0?1:-1)*dp(110)).alpha(0).setDuration(150)
                .withEndAction(()->{transitioning=false;restore(destination);}).start();
        }else restore(destination);
    }

    private void prepareBack(int edge){
        if(transitioning||backPreview)return;
        ScreenState target=history.peek();if(target==null)target=tabPages.get("home");
        if(target==null||target.page==content)return;
        content.animate().cancel();backEdge=edge;backPreview=true;previousPage=target.page;
        if(previousPage.getParent()==null)pages.addView(previousPage,0,new FrameLayout.LayoutParams(-1,-1));
        previousPage.setVisibility(View.VISIBLE);previousPage.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        content.bringToFront();pages.preview(content,true);
    }

    private void cancelBack(){
        if(content==null)return;
        final LinearLayout current=content;
        current.animate().cancel();current.animate().scaleX(1).scaleY(1).translationX(0).alpha(1).setDuration(200)
            .withEndAction(()->{if(current==content)finishBackPreview();}).start();
    }

    private void finishBackPreview(){
        if(previousPage!=null&&previousPage!=content)previousPage.setVisibility(View.INVISIBLE);
        previousPage=null;backPreview=false;pages.preview(content,false);
    }

    private void restore(ScreenState state){
        if(state.editor==null)new WindowInsetsControllerCompat(getWindow(),root).hide(WindowInsetsCompat.Type.ime());
        if(content!=null){content.animate().cancel();pages.removeView(content);}
        if(!history.isEmpty()&&history.peek()==state)history.pop();else history.clear();
        content=state.page;body=state.list;footer=state.bottom;messagesPanel=state.messages;scroll=state.scroller;headerActions=state.actions;
        notice=state.status;replyInput=state.editor;replySend=state.send;
        replyTemplates.clear();replyTemplates.addAll(state.templates);
        screen=state.name;tabFocus=state.focus;displayedTab=state.focus;threadId=state.thread;plate=state.recipient;
        currentMessages=state.records;lastInboxJSON=state.inboxJSON;lastThreadJSON=state.threadJSON;
        generation++;busy=false;polling=false;
        if(content.getParent()==null)pages.addView(content,new FrameLayout.LayoutParams(-1,-1));
        content.setVisibility(View.VISIBLE);content.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_AUTO);
        content.setScaleX(1);content.setScaleY(1);content.setTranslationX(0);content.setAlpha(1);content.bringToFront();
        finishBackPreview();notice.setText("");back.setEnabled(!screen.equals("home"));
        updateReplyControls();applyInsets();updateTabSelection(true);refreshVisibleConversation();
    }

    private static boolean isRootTab(String name){return name.equals("home")||name.equals("inbox")||name.equals("settings");}

    private void clearAccountUi(){
        generation++;history.clear();tabPages.clear();replyDrafts.clear();
        pages.removeAllViews();content=null;replyInput=null;currentMessages=new JSONArray();
    }

    private void createShell(){
        root=new FrameLayout(this);root.setBackgroundColor(Ui.BG);
        capture=new FrameLayout(this);capture.setBackground(orbs);root.addView(capture,new FrameLayout.LayoutParams(-1,-1));
        pages=new PageHost(this);capture.addView(pages,new FrameLayout.LayoutParams(-1,-1));
        tabBar();
        ViewCompat.setOnApplyWindowInsetsListener(root,(v,w)->{
            androidx.core.graphics.Insets sys=w.getInsets(WindowInsetsCompat.Type.systemBars()|WindowInsetsCompat.Type.displayCutout());
            systemTop=sys.top;systemBottom=sys.bottom;systemLeft=sys.left;systemRight=sys.right;keyboardBottom=w.getInsets(WindowInsetsCompat.Type.ime()).bottom;
            applyInsets();return w;
        });
        setContentView(root);
        root.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{if(r-l!=or-ol)applyInsets();});
    }

    private void applyInsets(){
        if(content==null)return;
        boolean tabs=isTabScreen(screen),keyboard=keyboardBottom>systemBottom+dp(24);
        int bottom=tabs&&!keyboard?0:Math.max(systemBottom,keyboardBottom)+dp(10);
        int width=root.getWidth()>0?root.getWidth():getResources().getDisplayMetrics().widthPixels;
        int horizontal=Math.max(dp(20),(width-systemLeft-systemRight-dp(680))/2);
        content.setPadding(horizontal+systemLeft,systemTop+dp(12),horizontal+systemRight,bottom);
        scroll.setPadding(0,0,0,tabs&&!keyboard?systemBottom+dp(100):dp(12));
        FrameLayout.LayoutParams lp=(FrameLayout.LayoutParams)tabBar.getLayoutParams();
        lp.bottomMargin=systemBottom+dp(12);
        lp.width=Math.min(dp(330),Math.max(dp(220),width-systemLeft-systemRight-dp(40)));
        tabBar.setLayoutParams(lp);tabBar.setVisibility(tabs&&!keyboard?View.VISIBLE:View.GONE);
    }
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
    /** 除對話（要俾 footer 輸入欄）外，所有頁都留住浮動 tab bar。 */
    private static boolean isTabScreen(String name){return !name.equals("conversation");}

    private void page(String title,String name){page(title,name,isTabScreen(name));}
    private void page(String title,String name,boolean tabs){
        finishBackPreview();
        if(content!=null){
            content.animate().cancel();
            if(isRootTab(screen))tabPages.put(screen,new ScreenState());
            if(isRootTab(name)){history.clear();pages.removeAllViews();}
            else if(!screen.equals(name)){history.push(new ScreenState());content.setVisibility(View.INVISIBLE);content.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);}
            else pages.removeView(content);
        }
        screen=name;busy=false;generation++;replyInput=null;replySend=null;messagesPanel=null;replyTemplates.clear();lastInboxJSON="";lastThreadJSON="";
        displayedTab=tabFocus;
        back.setEnabled(!name.equals("home"));
        content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);
        pages.addView(content,new FrameLayout.LayoutParams(-1,-1));
        if(!name.equals("home")){
            TextView backLink=new TextView(this);backLink.setText("‹ 返回");backLink.setTextSize(15);backLink.setTextColor(Ui.INK);backLink.setTypeface(null,Typeface.BOLD);
            backLink.setBackground(Ui.rippleStroke(dp(22),0xBFFFFFFF,dp(1),0x28FFFFFF));Ui.pressFeedback(backLink);
            backLink.setPadding(dp(14),dp(7),dp(14),dp(7));backLink.setOnClickListener(v->navigateBack());
            LinearLayout backWrap=new LinearLayout(this);backWrap.setGravity(Gravity.START);backWrap.setPadding(0,dp(8),dp(12),dp(10));backWrap.addView(backLink);content.addView(backWrap);
        }
        LinearLayout brandRow=new LinearLayout(this);brandRow.setGravity(Gravity.CENTER_VERTICAL);
        if(name.equals("home")){
            ImageView mark=new ImageView(this);mark.setImageResource(R.drawable.gorilla_mark);mark.setColorFilter(Ui.INK);
            LinearLayout.LayoutParams markLp=new LinearLayout.LayoutParams(dp(28),dp(28));markLp.rightMargin=dp(10);brandRow.addView(mark,markLp);
        }
        TextView brand=new TextView(this);brand.setText("GORILLA LEADING");brand.setTextSize(11);brand.setLetterSpacing(0);brand.setTextColor(Ui.MUTED);brandRow.addView(brand);content.addView(brandRow);
        LinearLayout titleRow=new LinearLayout(this);titleRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView heading=new TextView(this);heading.setText(title);heading.setTextSize(27);heading.setTypeface(null,Typeface.BOLD);heading.setTextColor(Ui.INK);heading.setPadding(0,dp(12),0,dp(12));
        titleRow.addView(heading,new LinearLayout.LayoutParams(0,-2,1));headerActions=new LinearLayout(this);titleRow.addView(headerActions);content.addView(titleRow);
        scroll=new ScrollView(this);scroll.setVerticalScrollBarEnabled(false);body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);scroll.addView(body);
        notice=new TextView(this);notice.setTextSize(13);notice.setTextColor(Ui.MUTED);notice.setPadding(0,dp(8),0,dp(8));
        final TextView statusView=notice;statusView.setVisibility(View.GONE);
        statusView.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence t,int s,int c,int a){}public void onTextChanged(CharSequence t,int s,int b,int c){statusView.setVisibility(t.length()==0?View.GONE:View.VISIBLE);}public void afterTextChanged(Editable t){}});
        footer=new LinearLayout(this);footer.setOrientation(LinearLayout.VERTICAL);
        if(tabs){
            // tab 頁：提示放喺列表上面，列表可以喺膠囊 bar 下面碌過（玻璃折射到內容）
            content.addView(notice);content.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
            scroll.setClipToPadding(false);scroll.setPadding(0,0,0,dp(148));
        }else{
            content.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));content.addView(notice);content.addView(footer);
        }
        scroll.setClipToPadding(false);applyInsets();updateTabSelection(true);
        ViewCompat.requestApplyInsets(root);
    }

    /** 懸浮膠囊 tab bar：真液態玻璃＋反光邊＋陰影（minSdk 35，全部裝置都有 AGSL）。 */
    private void tabBar(){
        tabBar=new FrameLayout(this);
        FrameLayout.LayoutParams barLp=new FrameLayout.LayoutParams(dp(330),dp(66),Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);
        barLp.bottomMargin=dp(12);root.addView(tabBar,barLp);
        // 膠囊底色墊底：玻璃初始化失敗兜底用
        tabBar.setBackground(Ui.glassFallback(dp(32)));
        tabBar.setElevation(dp(10));
        try{
            LiquidGlassView glass=new LiquidGlassView(this);
            // 深色染色保留背景透視；折射只集中於邊緣，避免扭曲文字。
            glass.setCornerRadius(dp(33));glass.setBlurRadius(dp(12));glass.setDispersion(0.025f);
            glass.setRefractionHeight(dp(12));glass.setRefractionOffset(dp(18));
            glass.setTintColorRed(.06f);glass.setTintColorGreen(.07f);glass.setTintColorBlue(.09f);glass.setTintAlpha(.58f);
            glass.setDraggableEnabled(false);glass.setElasticEnabled(false);glass.setTouchEffectEnabled(false);
            tabBar.addView(glass,new FrameLayout.LayoutParams(-1,-1));
            // 必須 bind 內容層（唔包含玻璃自己）：bind 容器會成棵 tree 畫入 RenderNode，
            // 包含玻璃會自己錄自己 → 第一 frame 崩潰。
            glass.bind(capture);tabBar.setBackground(null);tabGlassActive=true;
        }catch(RuntimeException|LinkageError t){tabBar.removeAllViews();tabGlassActive=false;tabBar.setBackground(Ui.glassFallback(dp(33)));}
        // 幼 rim 令邊緣透鏡一眼睇得出係玻璃（fallback 同真玻璃上面都用得；唔再用厚白反光環）
        View rim=new View(this);rim.setBackground(Ui.glassRim(dp(32)));rim.setClickable(false);rim.setFocusable(false);
        tabBar.addView(rim,new FrameLayout.LayoutParams(-1,-1));
        tabPill=new View(this);tabPill.setBackground(Ui.round(dp(27),0x25FFFFFF));tabBar.addView(tabPill,new FrameLayout.LayoutParams(-2,-2));
        LinearLayout tabRow=new LinearLayout(this);tabRow.setOrientation(LinearLayout.HORIZONTAL);tabBar.addView(tabRow,new FrameLayout.LayoutParams(-1,-1,Gravity.CENTER));
        String[] labels={"主頁","對話","設定"},targets={"home","inbox","settings"};int[] icons={R.drawable.ic_tab_home,R.drawable.ic_tab_chat,R.drawable.ic_tab_settings};
        for(int i=0;i<3;i++){
            final String target=targets[i];final boolean selected=tabFocus.equals(target);
            LinearLayout item=new LinearLayout(this);item.setOrientation(LinearLayout.VERTICAL);item.setGravity(Gravity.CENTER);item.setPadding(0,dp(10),0,dp(8));
            ImageView iconView=new ImageView(this);Drawable icon=Ui.icon(this,icons[i],0xCFFFFFFF);if(icon!=null)iconView.setImageDrawable(icon);tabIcons.add(iconView);
            item.addView(iconView,new LinearLayout.LayoutParams(dp(23),dp(23)));
            TextView label=new TextView(this);label.setText(labels[i]);label.setTextSize(11);label.setGravity(Gravity.CENTER);label.setTextColor(0xCFFFFFFF);label.setTypeface(null,Typeface.BOLD);tabLabels.add(label);
            item.addView(label,new LinearLayout.LayoutParams(-1,-2));
            tabRow.addView(item,new LinearLayout.LayoutParams(0,-1,1));
            item.setContentDescription(labels[i]);Ui.pressFeedback(item);
            item.setOnClickListener(v->{if(busy||transitioning||screen.equals(target))return;if(target.equals("home"))home();else if(target.equals("inbox"))inbox();else settings();});
        }
        tabBar.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{if(r-l!=or-ol)updateTabSelection(false);});
    }

    private void updateTabSelection(boolean animate){
        tabBar.post(()->{
            int cell=tabBar.getWidth()/3;if(cell<=0)return;
            FrameLayout.LayoutParams pillLp=(FrameLayout.LayoutParams)tabPill.getLayoutParams();
            pillLp.gravity=Gravity.TOP|Gravity.START;pillLp.width=cell-dp(10);pillLp.height=dp(54);pillLp.leftMargin=dp(5);pillLp.topMargin=dp(6);tabPill.setLayoutParams(pillLp);
            int selected=tabFocus.equals("inbox")?1:tabFocus.equals("settings")?2:0;
            tabPill.animate().cancel();
            if(animate)tabPill.animate().translationX(selected*cell).setDuration(290).setInterpolator(new android.view.animation.OvershootInterpolator(.45f)).start();
            else tabPill.setTranslationX(selected*cell);
            for(int i=0;i<tabIcons.size();i++){
                int color=i==selected?0xFF9BC3FF:0xDFFFFFFF;
                tabIcons.get(i).setColorFilter(color);tabLabels.get(i).setTextColor(color);
                ((View)tabIcons.get(i).getParent()).setSelected(i==selected);
            }
        });
    }

    private void text(String value){TextView v=new TextView(this);v.setText(value);v.setTextSize(16);v.setTextColor(Ui.INK);v.setPadding(0,dp(8),0,dp(8));body.addView(v);}
    private void section(String value){TextView v=new TextView(this);v.setText(value);v.setTextSize(13);v.setTypeface(null,Typeface.BOLD);v.setTextColor(Ui.MUTED);v.setPadding(dp(2),dp(24),0,dp(8));body.addView(v);}
    private void headerAction(int icon,String label,Runnable action){
        ImageButton button=new ImageButton(this);button.setImageDrawable(Ui.icon(this,icon,Ui.INK));button.setContentDescription(label);
        button.setBackground(Ui.ripple(dp(22),0xBFFFFFFF));button.setBackgroundTintList(null);button.setPadding(dp(12),dp(12),dp(12),dp(12));
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(dp(44),dp(44));lp.leftMargin=dp(6);headerActions.addView(button,lp);Ui.pressFeedback(button);button.setOnClickListener(v->{if(!busy)action.run();});
    }
    private void muted(String value){TextView v=new TextView(this);v.setText(value);v.setTextSize(13);v.setTextColor(Ui.MUTED);v.setPadding(0,dp(6),0,dp(6));body.addView(v);}
    private Button button(String label,Runnable action){Button v=Ui.secondaryButton(this,label);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,dp(52));lp.setMargins(0,dp(5),0,dp(5));body.addView(v,lp);v.setOnClickListener(w->{if(!busy)action.run();});return v;}
    private Button primary(String label,Runnable action){Button v=Ui.primaryButton(this,label);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,dp(52));lp.setMargins(0,dp(5),0,dp(5));body.addView(v,lp);v.setOnClickListener(w->{if(!busy)action.run();});return v;}
    private EditText field(String hint,int input){EditText value=new EditText(this);value.setHint(hint);value.setTextColor(Ui.INK);value.setHintTextColor(Ui.MUTED);value.setSingleLine(true);value.setInputType(input);value.setBackground(Ui.roundStroke(dp(16),0xDFFFFFFF,dp(1),0x1817202C));value.setBackgroundTintList(null);value.setPadding(dp(16),dp(14),dp(16),dp(14));value.setTextSize(15);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.setMargins(0,dp(5),0,dp(5));body.addView(value,lp);return value;}
    private boolean mine(JSONObject msg){if(msg.has("mine"))return msg.optBoolean("mine");return (!api.session.userId().isEmpty()&&api.session.userId().equals(msg.optString("authorId")))||api.session.sentByMe(msg.optString("id"));}
    private void task(Work work,Done done){
        if(previewMode){notice.setText("預覽不會傳送資料");return;}
        if(busy)return;busy=true;updateReplyControls();notice.setText("處理中…");int origin=generation;
        io.submit(()->{try{JSONObject result=work.run();runOnUiThread(()->{if(isFinishing()||isDestroyed()||origin!=generation)return;busy=false;updateReplyControls();notice.setText("");try{done.accept(result);}catch(Exception e){notice.setText("未能顯示回應，請重新整理");}});}
        catch(Exception e){runOnUiThread(()->{if(isDestroyed()||origin!=generation)return;busy=false;updateReplyControls();notice.setText(e.getMessage()==null?"連線失敗，請重試":e.getMessage());});}});
    }
    private void home(){
        tabFocus="home";
        page("泊車互助","home");
        section("發送提醒");
        primary("掃描車牌",()->{if(!api.session.onboarded()){onboarding();return;}startActivityForResult(new Intent(this,ScannerActivity.class),10);});
        button("手動輸入車牌",()->plateEntry(false));
        section("提醒對話");
        button("查看對話",this::inbox);
        section("我的車牌");button("車牌與提醒設定",this::settings);
        button("使用須知",()->Ui.showDialog(new AlertDialog.Builder(this).setTitle("泊車互助")
            .setMessage("只提供互助提醒，不提供咪錶繳費、代繳或罰單資訊認證。車牌可由多位獲授權駕駛者共同綁定。")
            .setPositiveButton("知道了",null),false));
    }
    private void onboarding(){page("先設定自己的車牌？","onboarding");text("同一車牌可以多人綁定，共同接收提醒。亦可略過，先幫其他人發提醒。");primary("設定車牌",()->{api.session.onboard();plateEntry(true);});button("略過，開始掃描",()->{api.session.onboard();startActivityForResult(new Intent(this,ScannerActivity.class),10);});}
    private void login(){login(this::settings);}
    private void login(Runnable afterLogin){
        page("電郵登入／註冊","login");EditText email=field("電郵地址",33);EditText code=field("6 位驗證碼",2);code.setFilters(new InputFilter[]{new InputFilter.LengthFilter(6)});
        text("以電郵驗證身分，無需先綁定車牌。驗證碼 10 分鐘內有效。");
        button("取得驗證碼",()->task(()->api.call("POST","auth/start",Api.data("email",email.getText().toString().trim().toLowerCase(Locale.ROOT)),false),r->notice.setText("驗證碼已寄出，請檢查收件匣／垃圾郵件；重新寄出需等 60 秒。")));
        primary("登入",()->task(()->api.call("POST","auth/verify",Api.data("email",email.getText().toString().trim().toLowerCase(Locale.ROOT),"code",code.getText().toString().trim()),false),r->{api.session.save(r.getString("token"));api.session.saveIdentity(r.optString("userId"));PushService.register(this);afterLogin.run();}));
    }
    private boolean requireLogin(){if(api.session.token().isEmpty()){login(screen.equals("composer")?this::composer:this::settings);return false;}return true;}
    private void settings(){
        tabFocus="settings";
        page("我的車牌與帳號","settings");
        text("只有自己或獲授權駕駛的車輛先綁定；這項聲明不等於平台核實車主身分。");
        section("連線服務");
        EditText server=field(api.session.baseUrl(),1);
        server.setText(api.session.baseUrl());
        primary("驗證並儲存網址",()->{String candidate=server.getText().toString();task(()->Api.data("base",api.validateServer(candidate)),r->{String value=r.getString("base");
            if(!value.equals(api.session.baseUrl()))clearAccountUi();
            api.session.setBaseUrl(value);settings();notice.setText("服務驗證成功，已儲存網址。");});});
        muted("更換 Tunnel 網址後需重新登入。");
        button("檢查應用程式更新",()->updates.check(true));
        if(!BuildConfig.FIREBASE_CONFIGURED)muted("此版本未設定 Firebase，遠端推送暫未啟用。");
        section("本機車牌草稿");
        for(String draft:api.session.plateDrafts()){
            button(draft+(api.session.token().isEmpty()?"　待登入":"　綁定"),()->{
                if(api.session.token().isEmpty()){login(this::settings);return;}
                task(()->api.call("POST","me/plates",Api.data("plate",draft,"authorisedDriver",true),true),r->{api.session.removePlateDraft(draft);settings();});
            });
            button("刪除草稿 "+draft,()->{api.session.removePlateDraft(draft);settings();}).setTextColor(0xFFD92D3E);
        }
        button("新增車牌草稿",()->plateEntry(true));muted("草稿只存在此手機；登入並綁定後才能接收提醒。");
        if(api.session.token().isEmpty()){primary("登入／註冊",this::login);return;}
        section("我的車牌");button("新增車牌",()->plateEntry(true));
        button("重新驗證登入",this::login);
        button("開啟手機通知",()->{
            if(!BuildConfig.FIREBASE_CONFIGURED){notice.setText("此 APK 未加入 Firebase 設定，遠端推送暫未啟用。");return;}
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},20);
            PushService.register(this);
            task(()->api.call("GET","capabilities",null,false),r->notice.setText(r.getJSONObject("push").optBoolean("fcm")?"已嘗試登記推送，請允許手機通知；實際接收仍受網絡及系統設定影響。":"後端等待 Firebase 私鑰設定，請先手動整理對話。"));
        });
        button("登出",()->task(()->{api.call("DELETE","me/devices/"+api.session.deviceId(),null,true);return api.call("POST","auth/logout",null,true);},r->{api.session.clear();clearAccountUi();PushService.cancelAll(this);home();}));
        button("刪除帳號及資料",()->Ui.showDialog(new AlertDialog.Builder(this).setTitle("永久刪除帳號？").setMessage("將刪除車牌綁定、登入及相關訊息，無法復原。").setNegativeButton("取消",null).setPositiveButton("刪除",(d,w)->task(()->api.call("DELETE","me",null,true),r->{api.session.clear();clearAccountUi();PushService.cancelAll(this);home();})),true)).setTextColor(0xFFD92D3E);
        task(()->api.call("GET","me/plates",null,true),r->{JSONArray rows=r.getJSONArray("plates");for(int i=0;i<rows.length();i++){String p=rows.getJSONObject(i).getString("plate");button("已綁定："+p+"　解除",()->Ui.showDialog(new AlertDialog.Builder(this).setTitle("解除 "+p+"？").setMessage("不會影響其他綁定者，你將失去收到的舊對話存取權。").setNegativeButton("取消",null).setPositiveButton("解除",(d,w)->task(()->api.call("DELETE","me/plates/"+Plate.canonical(p),null,true),v->settings())),true));}});
        text("對話建立後 7 日自動刪除。禁止騷擾、起底及爭執。墊款／還錢屬雙方自願安排，平台不處理金錢糾紛。");
    }
    private void plateEntry(boolean own){
        page(own?"綁定我的車牌":"輸入對方車牌","plate");
        EditText value=field("車牌（最多 8 字元）",1);value.setShowSoftInputOnFocus(false);value.setKeyListener(null);value.setLongClickable(false);value.setTypeface(Typeface.MONOSPACE);value.setTextSize(28);value.setGravity(Gravity.CENTER);
        String[] rows={"1234567890","ABCDEFGH","JKLMNPRS","TUVWXYZ"};
        for(String row:rows){LinearLayout keys=new LinearLayout(this);for(char c:row.toCharArray()){Button key=new Button(this);key.setMinWidth(0);key.setMinimumWidth(0);key.setMinHeight(0);key.setMinimumHeight(0);key.setPadding(0,0,0,0);key.setTextSize(17);key.setTextColor(Ui.INK);key.setBackground(Ui.ripple(dp(10),Ui.CARD));key.setBackgroundTintList(null);Ui.pressFeedback(key);key.setText(String.valueOf(c));LinearLayout.LayoutParams keyLp=new LinearLayout.LayoutParams(0,dp(48),1);keyLp.setMargins(dp(2),dp(2),dp(2),dp(2));keys.addView(key,keyLp);key.setOnClickListener(v->{if(value.length()<8)value.setText(value.getText().toString()+c);});}body.addView(keys);}
        button("空格",()->{if(value.length()>0&&value.length()<8&&!value.getText().toString().endsWith(" "))value.append(" ");});
        button("刪除上一個字元",()->{String p=value.getText().toString();if(!p.isEmpty())value.setText(p.substring(0,p.length()-1));});
        CheckBox consent=new CheckBox(this);consent.setText("我確認是車主或獲授權駕駛者，同意用車牌接收提醒。");if(own)body.addView(consent);
        primary(own?"綁定車牌":"確認車牌",()->{String p=value.getText().toString().trim();if(!Plate.valid(p)){notice.setText("請輸入有效車牌");return;}String normal=Plate.standard(p);if(normal!=null)p=normal;final String target=p;
            if(own){if(!consent.isChecked()){notice.setText("請先確認授權聲明");return;}if(api.session.token().isEmpty()){api.session.savePlateDraft(target);settings();notice.setText("已儲存本機草稿，登入後可正式綁定。");return;}task(()->api.call("POST","me/plates",Api.data("plate",target,"authorisedDriver",true),true),r->settings());}
            else checkRecipient(target);});
    }
    private void checkRecipient(String target){
        if(api.session.token().isEmpty()){login(()->checkRecipient(target));return;}
        task(()->api.call("POST","plates/lookup",Api.data("plate",target),true),r->{
            if(!r.optBoolean("available")){notice.setText("此車牌目前沒有可接收提醒的用戶。");return;}
            plate=target;sendText="留意入返咪錶";sendKey=UUID.randomUUID().toString();composer();
        });
    }
    private void composer(){
        page("提醒 "+plate,"composer");text("請再次核對車牌；所有綁定者共用同一條對話。");
        for(String t:new String[]{"小心違例泊車","留意入返咪錶","我幫你墊錢入咗咪錶"})button(t,()->{sendText=t;sendKey=UUID.randomUUID().toString();notice.setText("已選："+t);});
        EditText custom=field("自由輸入文字（最多 200 字）",1);custom.setFilters(new InputFilter[]{new InputFilter.LengthFilter(200)});
        text("「我幫你墊錢入咗咪錶」只是發送者的聲明，平台不核實付款，亦不參與咪錶繳費。");
        primary("發送提醒",()->{String message=custom.getText().toString().trim();if(message.isEmpty())message=sendText;sendText=message;if(!requireLogin())return;final String outgoing=message; final String targetPlate=plate;
            String payload=targetPlate+"\n"+outgoing;if(!payload.equals(lastSendPayload)){sendKey=UUID.randomUUID().toString();lastSendPayload=payload;}final String requestKey=sendKey;
            task(()->api.call("POST","threads",Api.data("plate",targetPlate,"text",outgoing,"idempotencyKey",requestKey),true),r->{api.session.markSent(r.optString("messageId"));threadId=r.getString("threadId");api.session.markCreatedThread(threadId);conversation();});});
    }
    private void inbox(){
        tabFocus="inbox";
        if(api.session.token().isEmpty()){login(this::inbox);return;}page("提醒對話","inbox");
        headerAction(R.drawable.ic_refresh,"重新整理對話",this::refreshVisibleConversation);
        task(()->api.call("GET","threads",null,true),this::renderInbox);
    }
    private void renderInbox(JSONObject result)throws Exception{
        String snapshot=result.getJSONArray("threads").toString();if(snapshot.equals(lastInboxJSON))return;lastInboxJSON=snapshot;
        body.removeAllViews();
        JSONArray rows=result.getJSONArray("threads");if(rows.length()==0){section("暫時沒有提醒");muted("收到的提醒會顯示在這裏。");}
        for(int i=0;i<rows.length();i++){
            JSONObject row=rows.getJSONObject(i);JSONObject last=row.optJSONObject("lastMessage");
            String preview=last==null?"提醒對話":(mine(last)?"你：":"對方：")+last.optString("text");
            double when=last!=null?last.optDouble("createdAt",0):row.optDouble("createdAt",0);
            LinearLayout card=new LinearLayout(this);card.setOrientation(LinearLayout.VERTICAL);card.setBackground(Ui.rippleStroke(dp(20),0xDFFFFFFF,dp(1),0x18FFFFFF));card.setPadding(dp(18),dp(17),dp(18),dp(17));Ui.pressFeedback(card);
            LinearLayout top=new LinearLayout(this);top.setOrientation(LinearLayout.HORIZONTAL);top.setGravity(Gravity.CENTER_VERTICAL);
            TextView plateView=new TextView(this);plateView.setText(row.optString("plate"));plateView.setTextSize(17);plateView.setTypeface(null,Typeface.BOLD);plateView.setTextColor(Ui.INK);
            TextView timeView=new TextView(this);timeView.setText(Ui.time(when));timeView.setTextSize(12);timeView.setTextColor(Ui.MUTED);
            top.addView(plateView,new LinearLayout.LayoutParams(0,-2,1));top.addView(timeView);card.addView(top,new LinearLayout.LayoutParams(-1,-2));
            TextView previewView=new TextView(this);previewView.setText(preview);previewView.setTextSize(14);previewView.setTextColor(0xFF55636B);previewView.setSingleLine(true);previewView.setEllipsize(TextUtils.TruncateAt.END);previewView.setPadding(0,dp(4),0,0);
            card.addView(previewView,new LinearLayout.LayoutParams(-1,-2));
            LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.setMargins(0,0,0,dp(10));body.addView(card,lp);
            card.setOnClickListener(v->{threadId=row.optString("id");plate=row.optString("plate");conversation();});
        }
    }
    private void conversation(){
        if(!previewMode&&api.session.token().isEmpty()){login(this::conversation);return;}page(plate,"conversation");
        headerAction(R.drawable.ic_refresh,"重新整理訊息",this::refreshVisibleConversation);
        messagesPanel=new LinearLayout(this);messagesPanel.setOrientation(LinearLayout.VERTICAL);body.addView(messagesPanel);
        final String targetThread=threadId;
        final ReplyDraft draft=replyDrafts.computeIfAbsent(targetThread,ignored->new ReplyDraft());
        LinearLayout chips=new LinearLayout(this);chips.setOrientation(LinearLayout.HORIZONTAL);
        for(String t:new String[]{"感謝師兄","唔該","多謝提醒"}){
            Button quick=Ui.secondaryButton(this,t);quick.setTextSize(13);quick.setTextColor(Ui.INK);
            quick.setMinHeight(0);quick.setMinimumHeight(0);quick.setMinWidth(0);quick.setMinimumWidth(0);quick.setPadding(dp(10),0,dp(10),0);
            LinearLayout.LayoutParams quickLp=new LinearLayout.LayoutParams(0,dp(40),1);quickLp.setMargins(0,0,dp(8),0);chips.addView(quick,quickLp);replyTemplates.add(quick);
            quick.setOnClickListener(v->{replyInput.setText(t);replyInput.setSelection(replyInput.length());notice.setText("");});
        }
        footer.addView(chips,new LinearLayout.LayoutParams(-1,-2));
        LinearLayout replyBar=new LinearLayout(this);replyBar.setOrientation(LinearLayout.HORIZONTAL);replyBar.setGravity(Gravity.CENTER_VERTICAL);
        replyInput=new EditText(this);replyInput.setHint("輸入回覆，或揀上面快捷句");replyInput.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE);replyInput.setMaxLines(3);replyInput.setFilters(new InputFilter[]{new InputFilter.LengthFilter(200)});
        replyInput.setTextColor(Ui.INK);replyInput.setHintTextColor(Ui.MUTED);replyInput.setBackgroundTintList(null);
        replyInput.setBackground(Ui.roundStroke(dp(24),0xEFFFFFFF,dp(1),0x1817202C));replyInput.setPadding(dp(18),dp(12),dp(18),dp(12));replyInput.setTextSize(15);
        replyBar.addView(replyInput,new LinearLayout.LayoutParams(0,-2,1));
        replySend=new Button(this);replySend.setText("↑");replySend.setAllCaps(false);replySend.setContentDescription("發送回覆");replySend.setTextSize(21);replySend.setTypeface(null,Typeface.BOLD);replySend.setTextColor(Color.WHITE);
        replySend.setBackground(Ui.ripple(dp(24),Ui.ACCENT));replySend.setMinHeight(0);replySend.setMinimumHeight(0);replySend.setMinWidth(0);replySend.setMinimumWidth(0);replySend.setPadding(0,0,0,0);
        replySend.setBackgroundTintList(null);Ui.pressFeedback(replySend);
        LinearLayout.LayoutParams sendLp=new LinearLayout.LayoutParams(dp(48),dp(48));sendLp.setMargins(dp(10),0,0,0);replyBar.addView(replySend,sendLp);
        LinearLayout.LayoutParams barLp=new LinearLayout.LayoutParams(-1,-2);barLp.topMargin=dp(10);footer.addView(replyBar,barLp);
        replyInput.setText(draft.text);
        replyInput.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence t,int start,int count,int after){}public void onTextChanged(CharSequence t,int start,int before,int count){draft.text=t.toString();updateReplyControls();}public void afterTextChanged(Editable t){}});
        replySend.setOnClickListener(v->{String value=replyInput.getText().toString().trim();if(busy||value.isEmpty())return;
            final String key=draft.beginAttempt(value);
            task(()->api.call("POST","threads/"+targetThread+"/messages",Api.data("text",value,"idempotencyKey",key),true),r->{api.session.markSent(r.optString("id"));draft.sent();replyInput.setText("");notice.setText("回覆已發送");refreshVisibleConversation();});});
        headerAction(R.drawable.ic_info,"舉報對話",()->Ui.showDialog(new AlertDialog.Builder(this).setTitle("舉報此對話？")
            .setNegativeButton("取消",null).setPositiveButton("舉報",(d,w)->task(()->api.call("POST","threads/"+targetThread+"/reports",Api.data("reason","用戶舉報不當訊息"),true),r->notice.setText("舉報已記錄，等待處理"))),true));
        updateReplyControls();if(!previewMode)task(()->api.call("GET","threads/"+targetThread+"/messages",null,true),this::renderMessages);
    }
    private void updateReplyControls(){
        if(replySend==null||replyInput==null)return;
        boolean canSend=!busy&&!replyInput.getText().toString().trim().isEmpty();replySend.setEnabled(canSend);replySend.setAlpha(canSend?1:.4f);replySend.setText(busy?"…":"↑");
        replyInput.setEnabled(!busy);for(Button quick:replyTemplates)quick.setEnabled(!busy);
    }
    private void renderMessages(JSONObject result)throws Exception{
        if(messagesPanel==null)return;String snapshot=result.getJSONArray("messages").toString();if(snapshot.equals(lastThreadJSON))return;lastThreadJSON=snapshot;
        boolean atBottom=scroll==null||scroll.getChildAt(0).getHeight()-scroll.getHeight()-scroll.getScrollY()<dp(100);
        boolean first=currentMessages.length()==0;
        currentMessages=result.getJSONArray("messages");messagesPanel.removeAllViews();
        if(currentMessages.length()>0)api.session.inferFirstAuthor(threadId,currentMessages.getJSONObject(0).optString("authorId"));
        if(currentMessages.length()==0)muted("暫時沒有訊息");
        for(int i=0;i<currentMessages.length();i++){
            JSONObject msg=currentMessages.getJSONObject(i);boolean mine=mine(msg);
            FrameLayout row=new FrameLayout(this);row.setPadding(0,dp(5),0,dp(5));
            LinearLayout bubble=new LinearLayout(this);bubble.setOrientation(LinearLayout.VERTICAL);
            bubble.setBackground(Ui.bubble(dp(19),mine?Ui.MINE:Ui.CARD,mine));bubble.setPadding(dp(14),dp(9),dp(14),dp(9));
            TextView bodyText=new TextView(this);bodyText.setText(msg.optString("text"));bodyText.setTextSize(16);bodyText.setTextColor(mine?Ui.MINE_INK:Ui.INK);
            bodyText.setMaxWidth(Math.min(dp(300),Math.max(dp(100),(int)(getResources().getDisplayMetrics().widthPixels*.76f)-dp(68))));bodyText.setLineSpacing(dp(2),1);
            TextView time=new TextView(this);time.setText(Ui.time(msg.optDouble("createdAt",0)));time.setTextSize(10);time.setTextColor(mine?0xCEFFFFFF:Ui.MUTED);time.setPadding(0,dp(5),0,0);
            bubble.addView(bodyText,new LinearLayout.LayoutParams(-2,-2));LinearLayout.LayoutParams timeLp=new LinearLayout.LayoutParams(-2,-2);timeLp.gravity=Gravity.END;bubble.addView(time,timeLp);
            bubble.setContentDescription((mine?"你：":"對方：")+msg.optString("text"));bubble.setTag(mine?"message.outgoing":"message.incoming");
            row.addView(bubble,new FrameLayout.LayoutParams(-2,-2,mine?Gravity.END:Gravity.START));messagesPanel.addView(row,new LinearLayout.LayoutParams(-1,-2));
            if(!mine)bubble.setOnLongClickListener(w->{Ui.showDialog(new AlertDialog.Builder(this).setTitle("封鎖此發送者？").setMessage("之後不會再互相接收提醒。").setNegativeButton("取消",null).setPositiveButton("封鎖",(d,n)->task(()->api.call("POST","blocks",Api.data("userId",msg.optString("authorId")),true),r->inbox())),true);return true;});
        }
        if(scroll!=null&&(atBottom||first))scroll.post(()->scroll.fullScroll(View.FOCUS_DOWN));
    }

    void previewInboxForTesting(JSONObject fixture) throws Exception {
        if(!BuildConfig.DEBUG)throw new IllegalStateException("Debug UI fixture only");
        previewMode=true;tabFocus="inbox";page("提醒對話","inbox");renderInbox(fixture);
    }

    void previewMessagesForTesting(JSONObject fixture) throws Exception {
        if(!BuildConfig.DEBUG||!previewMode)throw new IllegalStateException("Debug UI fixture only");
        renderMessages(fixture);
    }
    private void refreshVisibleConversation(){
        if(previewMode||!resumed||busy||polling||api.session.token().isEmpty()||(!screen.equals("conversation")&&!screen.equals("inbox")))return;
        polling=true;int origin=generation;boolean isThread=screen.equals("conversation");String path=isThread?"threads/"+threadId+"/messages":"threads";
        io.submit(()->{try{JSONObject result=api.call("GET",path,null,true);runOnUiThread(()->{polling=false;if(isFinishing()||isDestroyed()||!resumed||origin!=generation)return;try{if(isThread)renderMessages(result);else renderInbox(result);}catch(Exception e){notice.setText("未能更新對話，請稍後重試");}});}
            catch(Exception e){runOnUiThread(()->{polling=false;if(resumed&&origin==generation)notice.setText("自動更新暫未完成；可手動重試。回覆草稿已保留。");});}});
    }
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==10&&result==RESULT_OK&&data!=null)checkRecipient(data.getStringExtra("plate"));}
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] grants){super.onRequestPermissionsResult(request,permissions,grants);if(request==20)PushService.register(this);}
    @Override protected void onResume(){super.onResume();resumed=true;if(orbs!=null)orbs.start();live.removeCallbacks(poll);live.postDelayed(poll,5000);if(api!=null)PushService.register(this);if(updates!=null)updates.resumed();}
    @Override protected void onPause(){resumed=false;if(orbs!=null)orbs.stop();live.removeCallbacks(poll);super.onPause();}
    @Override protected void onDestroy(){if(orbs!=null)orbs.stop();if(updates!=null)updates.close();live.removeCallbacks(poll);io.shutdown();super.onDestroy();}
}
