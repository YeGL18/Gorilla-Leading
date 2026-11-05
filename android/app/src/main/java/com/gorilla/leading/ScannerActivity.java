package com.gorilla.leading;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Outline;
import android.graphics.Rect;
import android.os.*;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.*;
import androidx.activity.ComponentActivity;
import androidx.activity.EdgeToEdge;
import androidx.camera.core.*;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.*;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;
import java.util.*;
import java.util.concurrent.*;

public class ScannerActivity extends ComponentActivity {
    private PreviewView preview;private LinearLayout results;private TextView hint;
    private final ExecutorService cameraExecutor=Executors.newSingleThreadExecutor();
    private final TextRecognizer recognizer=TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);
    private ProcessCameraProvider provider;private volatile boolean processing=false,active=false;private long lastFrame=0;
    private List<String> displayed=new ArrayList<>();
    private final Map<String,Long> recent=new LinkedHashMap<>();private final Handler timer=new Handler(Looper.getMainLooper());
    private final Runnable expiry=new Runnable(){public void run(){renderCandidates();timer.postDelayed(this,500);}};
    @Override public void onCreate(Bundle state){super.onCreate(state);EdgeToEdge.enable(this);LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);
        root.setBackground(Ui.gradient(0xFFF4F7F8,0xFFE4EAEC,0));
        ViewCompat.setOnApplyWindowInsetsListener(root,(v,w)->{androidx.core.graphics.Insets s=w.getInsets(WindowInsetsCompat.Type.systemBars()|WindowInsetsCompat.Type.ime());v.setPadding(dp(20),s.top+dp(12),dp(20),s.bottom+dp(12));return w;});
        hint=new TextView(this);hint.setText("對準完整車牌，結果會保留 4 秒；撳車牌確認");hint.setTextSize(15);hint.setTextColor(Ui.MUTED);hint.setPadding(dp(2),dp(6),dp(2),dp(10));root.addView(hint);
        preview=new PreviewView(this);
        preview.setOutlineProvider(new ViewOutlineProvider(){@Override public void getOutline(View v,Outline o){o.setRoundRect(0,0,v.getWidth(),v.getHeight(),dp(20));}});
        preview.setClipToOutline(true);
        LinearLayout.LayoutParams previewLp=new LinearLayout.LayoutParams(-1,0,1);previewLp.topMargin=dp(2);root.addView(preview,previewLp);
        results=new LinearLayout(this);results.setOrientation(LinearLayout.VERTICAL);results.setPadding(0,dp(10),0,dp(4));root.addView(results);
        Button back=Ui.secondaryButton(this,"返回／手動輸入");
        LinearLayout.LayoutParams backLp=new LinearLayout.LayoutParams(-1,dp(52));backLp.topMargin=dp(8);root.addView(back,backLp);
        back.setOnClickListener(v->finish());setContentView(root);
        if(checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{Manifest.permission.CAMERA},11);
    }
    private int dp(int value){return Ui.dp(this,value);}
    @Override protected void onResume(){super.onResume();active=true;timer.post(expiry);if(checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)startCamera();}
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] grants){super.onRequestPermissionsResult(request,permissions,grants);if(request==11&&grants.length>0&&grants[0]==PackageManager.PERMISSION_GRANTED)startCamera();else hint.setText("相機權限未開啟，請返回使用手動輸入");}
    @androidx.annotation.OptIn(markerClass = androidx.camera.core.ExperimentalGetImage.class)
    private void startCamera(){
        ListenableFuture<ProcessCameraProvider> future=ProcessCameraProvider.getInstance(this);
        future.addListener(()->{try{
            if(!active)return;provider=future.get();provider.unbindAll();
            Preview view=new Preview.Builder().build();view.setSurfaceProvider(preview.getSurfaceProvider());
            ImageAnalysis analysis=new ImageAnalysis.Builder().setTargetResolution(new android.util.Size(1280,720)).setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build();
            analysis.setAnalyzer(cameraExecutor,image->{
                if(!active||processing||System.currentTimeMillis()-lastFrame<250||image.getImage()==null){image.close();return;}
                processing=true;lastFrame=System.currentTimeMillis();
                InputImage frame=InputImage.fromMediaImage(image.getImage(),image.getImageInfo().getRotationDegrees());
                recognizer.process(frame).addOnSuccessListener(text->{
                    List<Plate.Segment> segments=new ArrayList<>();
                    for(Text.TextBlock block:text.getTextBlocks())for(Text.Line line:block.getLines()){
                        Rect r=line.getBoundingBox();if(r!=null)segments.add(new Plate.Segment(line.getText(),r.left,r.top,r.width(),r.height()));
                    }
                    if(!active)return;long now=System.currentTimeMillis();for(String candidate:Plate.candidates(segments))recent.put(candidate,now);renderCandidates();
                }).addOnFailureListener(error->{if(active)hint.setText("未能辨識，請拉近或返回手動輸入");})
                  .addOnCompleteListener(result->{processing=false;image.close();});
            });
            provider.bindToLifecycle(this,CameraSelector.DEFAULT_BACK_CAMERA,view,analysis);
        }catch(Exception e){hint.setText("相機暫時不可用，請返回手動輸入");}},ContextCompat.getMainExecutor(this));
    }
    private void renderCandidates(){if(!active)return;long now=System.currentTimeMillis();recent.entrySet().removeIf(e->now-e.getValue()>=4000);
        List<String> current=new ArrayList<>(recent.keySet());if(current.equals(displayed))return;displayed=current;
        results.removeAllViews();int count=0;for(String plate:recent.keySet()){if(count++>=6)break;Button button=Ui.primaryButton(this,"確認 "+plate);button.setOnClickListener(v->{setResult(RESULT_OK,new Intent().putExtra("plate",plate));finish();});LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,dp(52));lp.setMargins(0,dp(4),0,dp(4));results.addView(button,lp);}}
    @Override protected void onPause(){active=false;timer.removeCallbacks(expiry);if(provider!=null)provider.unbindAll();super.onPause();}
    @Override protected void onDestroy(){recognizer.close();cameraExecutor.shutdown();super.onDestroy();}
}
