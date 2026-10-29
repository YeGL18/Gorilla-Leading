package com.gorilla.leading;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Rect;
import android.os.*;
import android.widget.*;
import androidx.activity.ComponentActivity;
import androidx.camera.core.*;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
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
    @Override public void onCreate(Bundle state){super.onCreate(state);LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setPadding(20,70,20,40);
        hint=new TextView(this);hint.setText("對準完整車牌，結果會保留 4 秒；撳車牌確認");hint.setTextSize(18);root.addView(hint);
        preview=new PreviewView(this);root.addView(preview,new LinearLayout.LayoutParams(-1,0,1));
        results=new LinearLayout(this);results.setOrientation(LinearLayout.VERTICAL);root.addView(results);
        Button back=new Button(this);back.setText("返回／手動輸入");back.setOnClickListener(v->finish());root.addView(back);setContentView(root);
        if(checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{Manifest.permission.CAMERA},11);
    }
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
        results.removeAllViews();int count=0;for(String plate:recent.keySet()){if(count++>=6)break;Button button=new Button(this);button.setText("確認 "+plate);button.setOnClickListener(v->{setResult(RESULT_OK,new Intent().putExtra("plate",plate));finish();});results.addView(button);}}
    @Override protected void onPause(){active=false;timer.removeCallbacks(expiry);if(provider!=null)provider.unbindAll();super.onPause();}
    @Override protected void onDestroy(){recognizer.close();cameraExecutor.shutdown();super.onDestroy();}
}
