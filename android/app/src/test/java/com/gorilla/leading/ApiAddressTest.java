package com.gorilla.leading;

import org.junit.Test;
import static org.junit.Assert.*;

public class ApiAddressTest {
    @Test public void acceptsHostOrFullBaseWithoutChangingTheOrigin() throws Exception {
        assertEquals("https://test.example/v1/parking-community",Api.normalizedBase(" https://test.example/ "));
        assertEquals("https://test.example:8443/v1/parking-community",Api.normalizedBase("https://test.example:8443/v1/parking-community/"));
    }
    @Test public void rejectsCredentialsInsecureUrlsQueriesAndUnrelatedPaths(){
        for(String value:new String[]{"http://test.example","https://user:pass@test.example","https://test.example/?token=secret","https://test.example/#fragment","https://test.example/login","not a URL"}){
            try{Api.normalizedBase(value);fail(value);}catch(Exception expected){}
        }
    }
}
