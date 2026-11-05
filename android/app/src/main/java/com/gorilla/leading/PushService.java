package com.gorilla.leading;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.*;
import java.util.concurrent.Executors;

public class PushService extends FirebaseMessagingService {
    static void channel(Context context){NotificationManager manager=context.getSystemService(NotificationManager.class);manager.createNotificationChannel(new NotificationChannel("parking_reminders","泊車互助提醒",NotificationManager.IMPORTANCE_HIGH));}
    static void cancelAll(Context context){context.getSystemService(NotificationManager.class).cancelAll();}
    static void register(Context context){
        if(!BuildConfig.FIREBASE_CONFIGURED||new Session(context).token().isEmpty())return;
        if(context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)return;
        if(FirebaseApp.getApps(context).isEmpty())FirebaseApp.initializeApp(context);
        FirebaseMessaging.getInstance().setAutoInitEnabled(true);
        FirebaseMessaging.getInstance().getToken().addOnSuccessListener(token->upload(context,token));
    }
    private static void upload(Context context,String token){
        Api api=new Api(context);if(api.session.token().isEmpty())return;
        java.util.concurrent.ExecutorService worker=Executors.newSingleThreadExecutor();worker.execute(()->{try{api.call("PUT","me/devices/"+api.session.deviceId(),Api.data("provider","fcm","token",token),true);}catch(Exception ignored){}finally{worker.shutdown();}});
    }
    @Override public void onNewToken(String token){upload(this,token);}
    @Override public void onMessageReceived(RemoteMessage message){
        if(new Session(this).token().isEmpty())return;
        if(checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)return;
        String thread=message.getData().get("threadId");if(thread==null)return;
        channel(this);Intent intent=new Intent(this,MainActivity.class).putExtra("threadId",thread).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pending=PendingIntent.getActivity(this,thread.hashCode(),intent,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        Notification notification=new Notification.Builder(this,"parking_reminders").setSmallIcon(com.gorilla.leading.R.drawable.ic_notification)
            .setContentTitle("泊車互助提醒").setContentText("你有新的提醒或回覆，撳此查看。")
            .setAutoCancel(true).setContentIntent(pending).setVisibility(Notification.VISIBILITY_PRIVATE).build();
        getSystemService(NotificationManager.class).notify(thread.hashCode(),notification);
    }
}
