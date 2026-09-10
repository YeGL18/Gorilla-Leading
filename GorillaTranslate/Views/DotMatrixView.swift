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

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let target = Int(speed)
        let colorChanged = context.coordinator.lastColor != dynamicColorHex
        let speedChanged = context.coordinator.lastSentTarget != target

        guard speedChanged || colorChanged else { return }

        if speedChanged {
            context.coordinator.lastSentTarget = target
            webView.evaluateJavaScript("target=\(target)")
        }
        if colorChanged {
            context.coordinator.lastColor = dynamicColorHex
            webView.evaluateJavaScript("updateColor('\(dynamicColorHex)')")
        }
    }

    final class Coordinator {
        var lastSentTarget: Int?
        var lastColor: String = "#ffd700"
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
        var dots=[],cx,cy,mr,target=0,display=0,raf=null,lastTs=0,accumPhase=0;
        var dpr=Math.min(2,window.devicePixelRatio||1);
        var activeColor='#ffd700', idleColor='#b8860b';

        function updateColor(hex){
            activeColor=hex;
            // 計算較暗嘅版本作為 idle 顏色
            var r=parseInt(hex.slice(1,3),16),g=parseInt(hex.slice(3,5),16),b=parseInt(hex.slice(5,7),16);
            idleColor='rgb('+Math.floor(r*0.7)+','+Math.floor(g*0.7)+','+Math.floor(b*0.7)+')';
        }

        function resize(){
            canvas.width=canvas.clientWidth*dpr;canvas.height=canvas.clientHeight*dpr;
            blurCanvas.width=canvas.width;blurCanvas.height=canvas.height;
            cx=canvas.clientWidth/2;cy=canvas.clientHeight/2;mr=Math.sqrt(cx*cx+cy*cy);gen();
        }

        function gen(){
            dots=[];var gap=13,extra=4,cols=Math.ceil(cx*2/gap)+extra,rows=Math.ceil(cy*2/gap)+extra,w=cx*2,h=cy*2;
            for(var r=-extra/2;r<rows;r++)for(var c=-extra/2;c<cols;c++){
                var bx=(c+0.5)*gap,by=(r+0.5)*gap;
                var dx=bx-cx,dy=by-cy,nr=Math.sqrt(dx*dx+dy*dy)/Math.max(1,mr);
                dots.push({bx,by,dx,dy,nr,gx:bx/w,gy:by/h});
            }
        }

        function distort(d, norm, w, h) {
            var influence = Math.min(cx, cy) * 0.35;
            var maxPull = Math.min(cx, cy) * 0.15 * norm;
            var t, r, arc, falloff;

            t = d.bx / w;
            arc = 4 * t * (1 - t);
            r = d.by / influence;
            falloff = 1 / (1 + r * Math.sqrt(r));
            var dy = arc * falloff * maxPull;

            r = (h - d.by) / influence;
            falloff = 1 / (1 + r * Math.sqrt(r));
            dy -= arc * falloff * maxPull;

            t = d.by / h;
            arc = 4 * t * (1 - t);
            r = d.bx / influence;
            falloff = 1 / (1 + r * Math.sqrt(r));
            var dx = arc * falloff * maxPull;

            r = (w - d.bx) / influence;
            falloff = 1 / (1 + r * Math.sqrt(r));
            dx -= arc * falloff * maxPull;

            return {px: d.bx + dx, py: d.by + dy};
        }

        function draw(ts){
            var s=display,norm=s/240;
            ctx.clearRect(0,0,canvas.width,canvas.height);
            ctx.save();ctx.scale(dpr,dpr);
            ctx.globalCompositeOperation='screen';
            var w=canvas.clientWidth,h=canvas.clientHeight;
            var pf=0.0008+norm*0.0012,rw=0.14,ra=Math.min(1.2,norm*6);
            var dt=lastTs?ts-lastTs:0;lastTs=ts;accumPhase+=dt*pf;
            var phase=accumPhase%1;

            if(norm<0.01){
                for(var i=0;i<dots.length;i++){
                    var d=dots[i];var p=distort(d,norm,w,h);
                    ctx.globalAlpha=0.35;ctx.fillStyle=idleColor;
                    ctx.beginPath();ctx.arc(p.px,p.py,0.8,0,Math.PI*2);ctx.fill();
                }
                ctx.restore();return;
            }

            var sd=Math.max(0,(norm-80/240)/(1-80/240));
            var rd=[];
            for(var i=0;i<dots.length;i++){
                var d=dots[i];
                var p=distort(d,norm,w,h);
                var px=p.px,py=p.py;
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
                rd.push({px:px,py:py,rip:rip,rad:rad,dm:dm,op:op,glow:glow});
            }

            bCtx.clearRect(0,0,blurCanvas.width,blurCanvas.height);
            bCtx.save();bCtx.scale(dpr,dpr);
            for(var i=0;i<rd.length;i++){
                var r=rd[i];
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

            for(var i=0;i<rd.length;i++){
                var r=rd[i];
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
            var diff=target-display;
            display+=Math.abs(diff)>0.3?diff*0.12:diff*0.5;
            draw(ts||0);raf=requestAnimationFrame(loop);
        }

        window.addEventListener('resize',function(){resize();});
        resize();raf=requestAnimationFrame(loop);
        </script>
        </body>
        </html>
        """
    }
}
