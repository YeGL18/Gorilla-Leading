package com.gorilla.leading;

import java.text.Normalizer;
import java.util.*;

final class Plate {
    static final String LETTERS="ABCDEFGHJKLMNPRSTUVWXYZ";
    static String canonical(String text) { return Normalizer.normalize(text,Normalizer.Form.NFKC).toUpperCase(Locale.ROOT).replaceAll("\\s+", ""); }
    static String standard(String text) { String p=canonical(text);return p.matches("(?:[A-HJ-NPR-Z]{1,2})?[1-9][0-9]{0,3}")?p:null; }
    static boolean valid(String text) {return text.matches("[A-HJ-NPR-Z0-9 ]{1,8}")&&!text.trim().isEmpty();}
    static final class Segment {
        final String text;final float x,y,w,h;
        Segment(String t,float x,float y,float w,float h){text=t;this.x=x;this.y=y;this.w=w;this.h=h;}
    }
    private static Segment union(String text,Segment a,Segment b){
        float x=Math.min(a.x,b.x),y=Math.min(a.y,b.y);
        return new Segment(text,x,y,Math.max(a.x+a.w,b.x+b.w)-x,Math.max(a.y+a.h,b.y+b.h)-y);
    }
    private static boolean contains(Segment a,Segment b){return a.x<=b.x&&a.y<=b.y&&a.x+a.w>=b.x+b.w&&a.y+a.h>=b.y+b.h;}
    static List<String> candidates(List<Segment> original) {
        List<Segment> input=new ArrayList<>(original.subList(0,Math.min(180,original.size())));
        List<Segment> digits=new ArrayList<>();for(Segment item:input)if(canonical(item.text).matches("[0-9]{1,3}"))digits.add(item);
        for(Segment a:digits)for(Segment b:digits){
            if(input.size()>=256)break;
            float height=Math.max(a.h,b.h);String text=canonical(a.text+b.text);
            if(text.length()<=4&&b.x>=a.x+a.w-height*.1&&b.x-a.x-a.w<=height*.8&&Math.abs(a.y+a.h/2-b.y-b.h/2)<=height*.4)
                input.add(union(text,a,b));
        }
        List<Segment> joined=new ArrayList<>();
        for(Segment a:input) {
            String prefix=canonical(a.text);if(!prefix.matches("[A-HJ-NPR-Z]{1,2}"))continue;
            for(Segment b:input) {
                String number=canonical(b.text);if(!number.matches("[0-9]{1,4}"))continue;
                float height=Math.max(a.h,b.h);
                boolean row=Math.abs(a.y+a.h/2-b.y-b.h/2)<=height*.5 && b.x>=a.x+a.w-height*.15 && b.x-a.x-a.w<=height*2;
                boolean lines=b.y>=a.y+a.h-height*.15 && b.y-a.y-a.h<=height*1.5 && Math.abs(a.x+a.w/2-b.x-b.w/2)<=Math.max(a.w,b.w)*.45;
                String candidate=standard(prefix+number);
                if((row||lines)&&candidate!=null)joined.add(union(candidate,a,b));
            }
        }
        List<Segment> candidates=new ArrayList<>(joined);
        for(Segment segment:input){String candidate=standard(segment.text);if(candidate==null)continue;
            boolean part=false;for(Segment full:joined)if(contains(full,segment)){part=true;break;}
            if(!part)candidates.add(new Segment(candidate,segment.x,segment.y,segment.w,segment.h));
        }
        LinkedHashSet<String> output=new LinkedHashSet<>();
        for(Segment candidate:candidates){boolean part=false;
            for(Segment full:candidates)if(full.text.length()>candidate.text.length()&&full.text.replaceAll("[0-9]+$", "").equals(candidate.text.replaceAll("[0-9]+$", ""))&&contains(full,candidate)){part=true;break;}
            if(!part)output.add(candidate.text);
        }
        List<String> result=new ArrayList<>(output);return result.subList(0,Math.min(6,result.size()));
    }
}
