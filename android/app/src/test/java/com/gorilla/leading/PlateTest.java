package com.gorilla.leading;
import org.junit.Test;
import static org.junit.Assert.*;
import java.util.*;
public class PlateTest {
 @Test public void normalise(){assertEquals("AB1234",Plate.standard("AB\n1234"));assertEquals("AB1234",Plate.standard("ＡＢ １２３４"));assertNull(Plate.standard("ABI234"));assertNull(Plate.standard("AB0123"));}
 @Test public void combine(){List<String> result=Plate.candidates(Arrays.asList(new Plate.Segment("AB",35,10,40,20),new Plate.Segment("1234",20,35,70,20)));assertEquals(Collections.singletonList("AB1234"),result);}
 @Test public void groupedDigits(){List<String> result=Plate.candidates(Arrays.asList(new Plate.Segment("AB",10,10,40,20),new Plate.Segment("12",55,10,25,20),new Plate.Segment("34",85,10,25,20)));assertEquals(Collections.singletonList("AB1234"),result);}
 @Test public void rejectDistant(){List<String> result=Plate.candidates(Arrays.asList(new Plate.Segment("AB",10,10,40,20),new Plate.Segment("1234",300,90,70,20)));assertFalse(result.contains("AB1234"));}
}
