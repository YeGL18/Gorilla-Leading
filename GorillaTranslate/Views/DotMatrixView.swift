import SwiftUI
import WebKit

struct DotMatrixView: View {
    @Binding var speed: Double
    var accentColor: Color = Color.yellow
    /// 黑武士模式下時速超過 100 時嘅動態顏色
    var dynamicColorHex: String = "#ffd700"

    private var resolvedAccentColor: Color {
        let gold = Color(hex: "FFC46D") ?? .yellow
        let red = Color(hex: "FF4500") ?? .red
        if dynamicColorHex != "#ffd700" && speed > 100 {
            let t = min(1.0, (speed - 100) / 100)
            return Color.blend(from: gold, to: red, amount: t)
        }
        return accentColor
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                DotMatrixWebView(speed: $speed, dynamicColorHex: dynamicColorHex)
                    .clipShape(.rect(cornerRadius: 16))

                VStack(spacing: 0) {
                    Spacer()
                    Text("\(Int(speed))")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: Int(speed))
                    Text("km/h")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
            }

            HStack {
                Text(String(localized: "目标时速"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(speed))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [resolvedAccentColor, .orange], startPoint: .leading, endPoint: .trailing)
                    )
                    .contentTransition(.numericText())
                Text("km/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, -4)
            }

            Slider(value: $speed, in: 0...240, step: 1)
                .tint(resolvedAccentColor)
        }
    }
}

struct DotMatrixWebView: UIViewRepresentable {
    @Binding var speed: Double
    /// canvas 嘅 CSS 縮放。時速頁傳 1.0（靠超大 canvas＋更多圓點鋪滿，
    /// 唔放大圓點）；demo 頁維持原本嘅 1.15。
    var canvasScale: CGFloat = 1.15
    /// 黑武士模式下的動態顏色（hex string，例如 "#ffd700"）
    var dynamicColorHex: String = "#ffd700"
    @Environment(\.scenePhase) private var scenePhase

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        context.coordinator.pendingRestore = (color: dynamicColorHex, target: Int(speed))
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 回前景自癒：後台掛起之後 WebKit 有機會停咗 rAF 唔再 fire，
        // 甚至成個 web content process 被系統收埋（canvas 變空白）——
        // 圓點動畫就會「消失」到成個 app 重開。JS 答到就踢返條動畫鏈；
        // 答唔到就成頁重新載入。
        if scenePhase == .active, let prev = context.coordinator.lastPhase, prev != .active {
            heal(webView, context: context)
        }
        context.coordinator.lastPhase = scenePhase

        let target = Int(speed)
        let colorChanged = context.coordinator.lastColor != dynamicColorHex
        let speedChanged = context.coordinator.lastSentTarget != target

        guard speedChanged || colorChanged else { return }
        if context.coordinator.pendingRestore != nil {
            context.coordinator.pendingRestore = (color: dynamicColorHex, target: target)
            return
        }

        if speedChanged {
            context.coordinator.lastSentTarget = target
            webView.evaluateJavaScript("target=\(target)")
        }
        if colorChanged {
            context.coordinator.lastColor = dynamicColorHex
            webView.evaluateJavaScript("updateColor('\(dynamicColorHex)')")
        }
    }

    /// 回前景探測：JS 應答到就只係 rAF 鏈斷咗，kick 返就得；
    /// 應答唔到（error）代表 web content process 死咗，成頁重新載入。
    private func heal(_ webView: WKWebView, context: Context) {
        let html = htmlContent
        let color = dynamicColorHex
        let target = Int(speed)
        webView.evaluateJavaScript("window.heal ? window.heal() : 0") { _, error in
            guard error != nil else { return }
            // JS 答唔到 = web content process 死咗，成頁重新載入先救得返。
            // 載入完成（didFinish）會經 pendingRestore 補送目標時速／顏色。
            context.coordinator.lastSentTarget = nil
            context.coordinator.lastColor = "#ffd700"
            context.coordinator.pendingRestore = (color: color, target: target)
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastSentTarget: Int?
        var lastColor: String = "#ffd700"
        var lastPhase: ScenePhase?
        /// 重新載入後要補送嘅狀態（等 didFinish 先送，唔係 JS 未 ready）
        var pendingRestore: (color: String, target: Int)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let restore = pendingRestore else { return }
            pendingRestore = nil
            webView.evaluateJavaScript("updateColor('\(restore.color)')")
            webView.evaluateJavaScript("target=\(restore.target)")
            lastColor = restore.color
            lastSentTarget = restore.target
        }
    }

    private var htmlContent: String {
        """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{background:transparent;overflow:hidden;height:100%;margin:0}
        html{height:100%;margin:0}
        canvas{position:absolute;top:0;left:0;width:100%;height:100%;transform:scale(\(canvasScale));transform-origin:center center}
        #blur{filter:blur(3px);pointer-events:none}
        </style>
        </head>
        <body>
        <canvas id="c"></canvas>
        <canvas id="blur"></canvas>
        <script>
        var canvas=document.getElementById('c'),ctx=canvas.getContext('2d');
        var blurCanvas=document.getElementById('blur'),bCtx=blurCanvas.getContext('2d');
        var dots=[],rendered=[],cx,cy,mr,viewWidth=0,viewHeight=0,target=0,display=0,raf=null,lastTs=0,accumPhase=0,lastFrameAt=0,lastIdleRendered=false;
        var dpr=Math.min(2,window.devicePixelRatio||1);
        var blurDpr=1;
        var activeColor='#ffd700', idleColor='#b8860b';

        function updateColor(hex){
            activeColor=hex;
            lastIdleRendered=false;
            // 計算較暗嘅版本作為 idle 顏色
            var r=parseInt(hex.slice(1,3),16),g=parseInt(hex.slice(3,5),16),b=parseInt(hex.slice(5,7),16);
            idleColor='rgb('+Math.floor(r*0.7)+','+Math.floor(g*0.7)+','+Math.floor(b*0.7)+')';
        }

        function resize(){
            viewWidth=canvas.clientWidth;viewHeight=canvas.clientHeight;
            canvas.width=Math.round(viewWidth*dpr);canvas.height=Math.round(viewHeight*dpr);
            blurCanvas.width=Math.round(viewWidth*blurDpr);blurCanvas.height=Math.round(viewHeight*blurDpr);
            cx=viewWidth/2;cy=viewHeight/2;mr=Math.sqrt(cx*cx+cy*cy);
            lastIdleRendered=false;gen();
        }

        function gen(){
            dots=[];rendered=[];
            var gap=13,extra=4,cols=Math.ceil(viewWidth/gap)+extra,rows=Math.ceil(viewHeight/gap)+extra;
            var influence=Math.min(cx,cy)*0.35,pull=Math.min(cx,cy)*0.15;
            for(var r=-extra/2;r<rows;r++)for(var c=-extra/2;c<cols;c++){
                var bx=(c+0.5)*gap,by=(r+0.5)*gap;
                var dx=bx-cx,dy=by-cy,nr=Math.sqrt(dx*dx+dy*dy)/Math.max(1,mr);
                var tx=by/viewHeight,ty=bx/viewWidth;
                var arcX=4*tx*(1-tx),arcY=4*ty*(1-ty);
                var left=Math.max(0,bx/influence),right=Math.max(0,(viewWidth-bx)/influence);
                var top=Math.max(0,by/influence),bottom=Math.max(0,(viewHeight-by)/influence);
                var pullX=arcX*(1/(1+left*Math.sqrt(left))-1/(1+right*Math.sqrt(right)))*pull;
                var pullY=arcY*(1/(1+top*Math.sqrt(top))-1/(1+bottom*Math.sqrt(bottom)))*pull;
                dots.push({bx,by,dx,dy,nr,pullX,pullY});
                rendered.push({px:0,py:0,rip:0,rad:0,dm:0,op:0,glow:0});
            }
        }

        function draw(ts){
            var s=display,norm=s/240;
            var pf=0.0008+norm*0.0012,rw=0.14,ra=Math.min(1.2,norm*6);
            var dt=lastTs?Math.min(ts-lastTs,100):0;lastTs=ts;accumPhase+=dt*pf;
            var phase=accumPhase%1;
            if(norm<0.01&&lastIdleRendered)return;
            ctx.clearRect(0,0,canvas.width,canvas.height);
            ctx.save();ctx.scale(dpr,dpr);
            ctx.globalCompositeOperation='screen';

            if(norm<0.01){
                bCtx.clearRect(0,0,blurCanvas.width,blurCanvas.height);
                for(var i=0;i<dots.length;i++){
                    var d=dots[i];var px=d.bx+d.pullX*norm,py=d.by+d.pullY*norm;
                    ctx.globalAlpha=0.35;ctx.fillStyle=idleColor;
                    ctx.beginPath();ctx.arc(px,py,0.8,0,Math.PI*2);ctx.fill();
                }
                ctx.restore();lastIdleRendered=true;return;
            }
            lastIdleRendered=false;

            var sd=Math.max(0,(norm-80/240)/(1-80/240));
            for(var i=0;i<dots.length;i++){
                var d=dots[i];
                var px=d.bx+d.pullX*norm,py=d.by+d.pullY*norm;
                var dn=Math.sqrt((px-cx)*(px-cx)+(py-cy)*(py-cy))/Math.max(1,mr),rip=0;
                for(var r=0;r<2;r++){
                    var rp=(phase+r*0.5)%1;if(rp<0.01)rp=0;
                    var bd=(dn-rp)/rw;
                    var ampl=(1-rp*0.5)*ra;
                    var theta=Math.min(Math.PI/2,Math.abs(bd)*Math.PI/2);
                    rip+=Math.cos(theta)*Math.cos(theta)*ampl;
                }
                var rad=Math.max(0.5,1.2*(1+rip*0.7));
                var cf=Math.abs(d.dx)/cx*Math.abs(d.dy)/cy;
                var dm=1-sd*cf*0.5;
                var op=Math.min(1,(0.4+norm*0.6)*(1+rip*0.3))*dm;
                var glow=norm>0.02&&d.nr>0.15?norm*d.nr*35*(0.8+rip*0.3):0;
                var out=rendered[i];
                out.px=px;out.py=py;out.rip=rip;out.rad=rad;out.dm=dm;out.op=op;out.glow=glow;
            }

            bCtx.clearRect(0,0,blurCanvas.width,blurCanvas.height);
            bCtx.save();bCtx.scale(blurDpr,blurDpr);
            for(var i=0;i<rendered.length;i++){
                var r=rendered[i];
                if(r.rip>0.05){
                    var angle=Math.atan2(r.py-cy,r.px-cx);
                    var tl=r.rip*7;
                    var ox=Math.cos(angle)*tl*0.3;
                    var oy=Math.sin(angle)*tl*0.3;
                    bCtx.save();
                    bCtx.translate(r.px+ox,r.py+oy);
                    bCtx.rotate(angle);
                    bCtx.globalAlpha=r.rip*0.8;
                    bCtx.fillStyle=activeColor;
                    bCtx.beginPath();
                    bCtx.ellipse(0,0,tl,1.0,0,0,Math.PI*2);
                    bCtx.fill();
                    bCtx.restore();
                }
            }
            bCtx.restore();

            for(var i=0;i<rendered.length;i++){
                var r=rendered[i];
                if(r.glow>0){
                    ctx.globalAlpha=r.glow*0.006*r.dm;ctx.fillStyle=activeColor;
                    ctx.beginPath();ctx.arc(r.px,r.py,r.rad+r.glow*0.06,0,Math.PI*2);ctx.fill();
                }
                ctx.globalAlpha=r.op;ctx.fillStyle=r.rip>0.08?activeColor:idleColor;
                ctx.beginPath();ctx.arc(r.px,r.py,r.rad,0,Math.PI*2);ctx.fill();
            }
            ctx.restore();
        }

        function loop(ts){
            lastFrameAt=performance.now();
            var diff=target-display;
            display+=Math.abs(diff)>0.3?diff*0.12:diff*0.5;
            draw(ts||0);raf=requestAnimationFrame(loop);
        }

        // 自癒：切背景／回前景之後 WebKit 有機會停咗 rAF 唔再 fire，
        // 圓點動畫會就咁「消失」到成個 app 重開。見到鏈斷咗就即刻重起。
        function kickLoop(){
            if(raf)cancelAnimationFrame(raf);
            lastTs=0;
            lastFrameAt=performance.now();
            raf=requestAnimationFrame(loop);
        }
        // native 回前景時叫一次：順手 resize（防止 canvas 尺寸卡住）＋重起動畫鏈
        window.heal=function(){resize();kickLoop();return 1;};
        document.addEventListener('visibilitychange',function(){
            if(!document.hidden&&performance.now()-lastFrameAt>250)kickLoop();
        });
        setInterval(function(){
            if(performance.now()-lastFrameAt>500)kickLoop();
        },500);

        window.addEventListener('resize',function(){resize();});
        resize();raf=requestAnimationFrame(loop);
        </script>
        </body>
        </html>
        """
    }
}
