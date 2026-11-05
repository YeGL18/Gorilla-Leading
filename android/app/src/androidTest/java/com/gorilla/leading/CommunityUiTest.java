package com.gorilla.leading;

import android.graphics.Bitmap;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.TextView;
import android.view.WindowInsets;
import android.view.inputmethod.InputMethodManager;
import android.content.Context;
import androidx.activity.BackEventCompat;
import androidx.activity.OnBackPressedCallback;
import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public class CommunityUiTest {
    private static Object field(MainActivity activity, String name) {
        try { Field f=MainActivity.class.getDeclaredField(name); f.setAccessible(true); return f.get(activity); }
        catch(Exception error) { throw new AssertionError(error); }
    }

    private static JSONObject inboxFixture() throws Exception {
        return new JSONObject("{\"threads\":[{\"id\":\"fixture-thread\",\"plate\":\"AB 1234\",\"createdAt\":1793500000,\"lastMessage\":{\"text\":\"留意入返咪錶\",\"mine\":false,\"createdAt\":1793500000}}]}");
    }

    private static JSONObject messagesFixture() throws Exception {
        return new JSONObject("{\"messages\":[{\"id\":\"1\",\"text\":\"留意入返咪錶，架車仲喺度。\",\"authorId\":\"other\",\"mine\":false,\"createdAt\":1793500000},{\"id\":\"2\",\"text\":\"唔該師兄，我而家過嚟。\",\"authorId\":\"self\",\"mine\":true,\"createdAt\":1793500040},{\"id\":\"3\",\"text\":\"收到，唔使急。\",\"authorId\":\"other\",\"mine\":false,\"createdAt\":1793500060},{\"id\":\"4\",\"text\":\"多謝提醒！\",\"authorId\":\"self\",\"mine\":true,\"createdAt\":1793500080}]}");
    }

    private static View findText(View view, String text) {
        if(view instanceof TextView && ((TextView)view).getText().toString().equals(text))return view;
        if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){
            View found=findText(((ViewGroup)view).getChildAt(i),text);if(found!=null)return found;
        }
        return null;
    }

    private static void capture(String name) throws Exception {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync();SystemClock.sleep(350);
        Bitmap screenshot=InstrumentationRegistry.getInstrumentation().getUiAutomation().takeScreenshot();
        File directory=new File(InstrumentationRegistry.getInstrumentation().getTargetContext().getExternalFilesDir(null),"ui-checks");
        assertTrue(directory.isDirectory()||directory.mkdirs());
        try(FileOutputStream output=new FileOutputStream(new File(directory,name+".png"))){assertTrue(screenshot.compress(Bitmap.CompressFormat.PNG,100,output));}
        screenshot.recycle();
    }

    @Test public void bubblesBackPreviewDraftAndPersistentShell() throws Exception {
        try(ActivityScenario<MainActivity> scenario=ActivityScenario.launch(MainActivity.class)){
            capture("home");
            final Object[] shell=new Object[3];
            scenario.onActivity(activity->{
                shell[0]=field(activity,"root");shell[1]=field(activity,"capture");shell[2]=field(activity,"tabBar");
                assertEquals("Real glass must bind successfully in the hardware emulator",true,field(activity,"tabGlassActive"));
                try {activity.previewInboxForTesting(inboxFixture());}catch(Exception e){throw new AssertionError(e);}
            });
            capture("inbox");
            scenario.onActivity(activity->{
                View plate=findText((View)field(activity,"body"),"AB 1234");assertNotNull(plate);
                ((View)plate.getParent().getParent()).performClick();
                try {activity.previewMessagesForTesting(messagesFixture());}catch(Exception e){throw new AssertionError(e);}
            });
            capture("conversation");
            scenario.onActivity(activity->{
                ViewGroup panel=(ViewGroup)field(activity,"messagesPanel");
                View incoming=((ViewGroup)panel.getChildAt(0)).getChildAt(0);
                View outgoing=((ViewGroup)panel.getChildAt(1)).getChildAt(0);
                assertEquals("message.incoming",incoming.getTag());assertEquals("message.outgoing",outgoing.getTag());
                assertTrue("Outgoing bubble must sit right of incoming bubble",outgoing.getLeft()>incoming.getLeft());
                assertTrue("Bubbles must not fill the row",outgoing.getWidth()<panel.getWidth());
                TextView incomingText=(TextView)((ViewGroup)incoming).getChildAt(0);
                assertTrue("Full message must not collapse to a single glyph",incomingText.getWidth()>Ui.dp(activity,140));
                assertEquals(incomingText.getText().length(),incomingText.getLayout().getLineEnd(incomingText.getLineCount()-1));
                ((EditText)field(activity,"replyInput")).setText("未發送的草稿");
                OnBackPressedCallback back=(OnBackPressedCallback)field(activity,"back");
                back.handleOnBackStarted(new BackEventCompat(0,400,0,BackEventCompat.EDGE_LEFT));
                back.handleOnBackProgressed(new BackEventCompat(100,400,.65f,BackEventCompat.EDGE_LEFT));
                assertSame(shell[0],field(activity,"root"));assertSame(shell[1],field(activity,"capture"));assertSame(shell[2],field(activity,"tabBar"));
                assertNotNull("Predictive back must have a real previous page",field(activity,"previousPage"));
                assertEquals(View.VISIBLE,((View)field(activity,"previousPage")).getVisibility());
            });
            capture("predictive-back");
            scenario.onActivity(activity->((OnBackPressedCallback)field(activity,"back")).handleOnBackCancelled());
            SystemClock.sleep(300);
            scenario.onActivity(activity->{
                assertEquals("未發送的草稿",((EditText)field(activity,"replyInput")).getText().toString());
                assertEquals(1f,((View)field(activity,"content")).getScaleX(),.001f);
                ((OnBackPressedCallback)field(activity,"back")).handleOnBackPressed();
            });
            SystemClock.sleep(300);
            scenario.onActivity(activity->{
                assertEquals("inbox",field(activity,"screen"));assertSame(shell[2],field(activity,"tabBar"));
                View plate=findText((View)field(activity,"body"),"AB 1234");((View)plate.getParent().getParent()).performClick();
            });
            scenario.onActivity(activity->assertEquals("未發送的草稿",((EditText)field(activity,"replyInput")).getText().toString()));
        }
    }

    @Test public void composerTracksKeyboardAndTabWidthIsBounded() throws Exception {
        try(ActivityScenario<MainActivity> scenario=ActivityScenario.launch(MainActivity.class)){
            scenario.onActivity(activity->{
                View bar=(View)field(activity,"tabBar");
                assertTrue(bar.getWidth()<=Ui.dp(activity,330)+1);
                try {activity.previewInboxForTesting(inboxFixture());}catch(Exception e){throw new AssertionError(e);}
                View plate=findText((View)field(activity,"body"),"AB 1234");((View)plate.getParent().getParent()).performClick();
            });
            scenario.onActivity(activity->{
                EditText editor=(EditText)field(activity,"replyInput");editor.setText("鍵盤測試");editor.requestFocus();
                ((InputMethodManager)activity.getSystemService(Context.INPUT_METHOD_SERVICE)).showSoftInput(editor,InputMethodManager.SHOW_IMPLICIT);
            });
            SystemClock.sleep(1200);
            capture("keyboard");
            scenario.onActivity(activity->{
                View root=(View)field(activity,"root"),send=(View)field(activity,"replySend");
                int ime=root.getRootWindowInsets().getInsets(WindowInsets.Type.ime()).bottom;
                assertTrue("Test keyboard must be visible",ime>0);
                int[] position=new int[2];send.getLocationOnScreen(position);
                int keyboardTop=activity.getWindowManager().getCurrentWindowMetrics().getBounds().height()-ime;
                assertTrue("Send button must stay directly above the keyboard",Math.abs(keyboardTop-position[1]-send.getHeight())<Ui.dp(activity,32));
                assertEquals(View.GONE,((View)field(activity,"tabBar")).getVisibility());
            });
        }
    }

    @Test public void tabSelectionSurvivesNavigationAndDialogUsesNativeWindow() throws Exception {
        try(ActivityScenario<MainActivity> scenario=ActivityScenario.launch(MainActivity.class)){
            final Object[] originalBar=new Object[1];
            scenario.onActivity(activity->{
                originalBar[0]=field(activity,"tabBar");
                try {activity.previewInboxForTesting(inboxFixture());}catch(Exception e){throw new AssertionError(e);}
            });
            scenario.onActivity(activity->{
                ViewGroup bar=(ViewGroup)field(activity,"tabBar");
                ViewGroup tabs=(ViewGroup)bar.getChildAt(bar.getChildCount()-1);
                tabs.getChildAt(0).performClick();
            });
            SystemClock.sleep(400);
            scenario.onActivity(activity->{
                assertEquals("home",field(activity,"screen"));assertSame(originalBar[0],field(activity,"tabBar"));
                assertEquals(0f,((View)field(activity,"tabPill")).getTranslationX(),.5f);
                ViewGroup bar=(ViewGroup)field(activity,"tabBar");
                ViewGroup tabs=(ViewGroup)bar.getChildAt(bar.getChildCount()-1);
                tabs.getChildAt(2).performClick();
            });
            capture("settings");
            scenario.onActivity(activity->{
                assertEquals("settings",field(activity,"screen"));assertSame(originalBar[0],field(activity,"tabBar"));
                ViewGroup bar=(ViewGroup)field(activity,"tabBar");
                assertEquals((bar.getWidth()/3)*2f,((View)field(activity,"tabPill")).getTranslationX(),1f);
                ((ViewGroup)bar.getChildAt(bar.getChildCount()-1)).getChildAt(0).performClick();
            });
            scenario.onActivity(activity->findText((View)field(activity,"body"),"使用須知").performClick());
            capture("notice-dialog");
            InstrumentationRegistry.getInstrumentation().getUiAutomation().performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK);
        }
    }

    @Test public void legacyInitialMessageUsesItsAuthorAndDoesNotMarkTheReplyAsMine() throws Exception {
        try(ActivityScenario<MainActivity> scenario=ActivityScenario.launch(MainActivity.class)){
            scenario.onActivity(activity->{
                Session session=((Api)field(activity,"api")).session;
                session.clear();
                try {
                    activity.previewInboxForTesting(new JSONObject(inboxFixture().toString().replace("fixture-thread","fixture-legacy")));
                    View plate=findText((View)field(activity,"body"),"AB 1234");((View)plate.getParent().getParent()).performClick();
                    session.markCreatedThread("fixture-legacy");
                    activity.previewMessagesForTesting(new JSONObject("{\"messages\":[{\"id\":\"legacy-first\",\"authorId\":\"fixture-self\",\"text\":\"留意入返咪錶\",\"createdAt\":1},{\"id\":\"legacy-reply\",\"authorId\":\"fixture-other\",\"text\":\"收到\",\"createdAt\":2}]}"));
                    ViewGroup panel=(ViewGroup)field(activity,"messagesPanel");
                    assertEquals("message.outgoing",((ViewGroup)panel.getChildAt(0)).getChildAt(0).getTag());
                    assertEquals("message.incoming",((ViewGroup)panel.getChildAt(1)).getChildAt(0).getTag());
                    assertEquals("fixture-self",session.userId());
                }catch(Exception error){throw new AssertionError(error);}finally{session.clear();}
            });
        }
    }

    @Test public void updateRequiresNewerVersionMatchingPackageAndMatchingSignature() throws Exception {
        Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();
        android.content.pm.PackageManager manager=context.getPackageManager();
        android.content.pm.PackageInfo installed=manager.getPackageInfo(context.getPackageName(),android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES);
        android.content.pm.PackageInfo candidate=manager.getPackageArchiveInfo(installed.applicationInfo.sourceDir,android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES);
        long version=installed.getLongVersionCode();
        installed.setLongVersionCode(version-1);
        AppUpdates.checkPackage(installed,candidate,context.getPackageName(),version);
        installed.setLongVersionCode(version);
        try{AppUpdates.checkPackage(installed,candidate,context.getPackageName(),version);fail("Same version accepted");}catch(Exception expected){}
        try{AppUpdates.checkPackage(installed,candidate,"another.package",version+1);fail("Wrong package accepted");}catch(Exception expected){}
        android.content.pm.PackageInfo foreign=manager.getPackageInfo("android",android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES);
        foreign.packageName=context.getPackageName();foreign.setLongVersionCode(version+1);
        try{AppUpdates.checkPackage(installed,foreign,context.getPackageName(),version+1);fail("Foreign signing certificate accepted");}catch(Exception expected){}
    }
}
