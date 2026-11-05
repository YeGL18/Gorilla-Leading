package com.gorilla.leading;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.UUID;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class Session {
    private final SharedPreferences prefs;
    Session(Context context) {
        prefs = context.getSharedPreferences("community", Context.MODE_PRIVATE);
        if (BuildConfig.API_BASE_URL.equals("https://api.lucidtelos.com/v1/parking-community")
                && !prefs.getBoolean("namedTunnelMigrated.v1", false)) {
            SharedPreferences.Editor edit = prefs.edit().putBoolean("namedTunnelMigrated.v1", true);
            String old = prefs.getString("apiOverride", "").trim();
            try {
                String host = java.net.URI.create(old).getHost();
                if (host != null && host.toLowerCase(java.util.Locale.ROOT).endsWith(".trycloudflare.com")) {
                    edit.remove("apiOverride");
                }
            } catch (IllegalArgumentException ignored) { }
            edit.apply();
        }
    }
    // A saved override lets a new tunnel host apply without rebuilding the APK.
    String baseUrl() {
        String override = prefs.getString("apiOverride", "").trim();
        return override.isEmpty() ? BuildConfig.API_BASE_URL : override;
    }
    void setBaseUrl(String value) { prefs.edit().putString("apiOverride", value.trim()).apply(); }
    // Tokens are scoped by API origin so a changed server never reuses an old session.
    private String scope() { return "session:" + baseUrl(); }
    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias("gorilla-community")) return (SecretKey)store.getKey("gorilla-community", null);
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder("gorilla-community", KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }
    String token() {
        return tokenFor(baseUrl());
    }
    String tokenFor(String base) {
        String storageKey="session:"+base;
        try {
            String value = prefs.getString(storageKey, ""); if (value.isEmpty()) return "";
            String[] parts = value.split(":");
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)));
            return new String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), StandardCharsets.UTF_8);
        } catch (Exception e) { prefs.edit().remove(storageKey).remove(storageKey+":user").apply(); return ""; }
    }
    void save(String token) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        String value = Base64.encodeToString(cipher.getIV(),Base64.NO_WRAP) + ":" + Base64.encodeToString(cipher.doFinal(token.getBytes(StandardCharsets.UTF_8)),Base64.NO_WRAP);
        if (!prefs.edit().putString(scope(),value).commit()) throw new Exception("無法安全儲存登入資料");
    }
    void clear() { prefs.edit().remove(scope()).remove(scope()+":user").apply(); }
    void saveIdentity(String id) { if(id!=null&&!id.isEmpty())prefs.edit().putString(scope()+":user",id).apply(); }
    String userId() { return prefs.getString(scope()+":user",""); }
    private String ownershipScope() { return scope()+":owner:"+userId(); }
    void markCreatedThread(String id) { remember("threads",id); }
    void inferFirstAuthor(String thread, String author) {
        if(userId().isEmpty()&&remembered("threads",thread))saveIdentity(author);
    }
    private void remember(String kind,String id) {
        if(id==null||id.isEmpty())return;
        String key=ownershipScope()+":"+kind;
        java.util.Set<String> values=new java.util.LinkedHashSet<>(prefs.getStringSet(key,java.util.Collections.emptySet()));
        values.add(id);while(values.size()>300)values.remove(values.iterator().next());
        prefs.edit().putStringSet(key,values).apply();
    }
    private boolean remembered(String kind,String id) {return prefs.getStringSet(ownershipScope()+":"+kind,java.util.Collections.emptySet()).contains(id);}
    void savePlateDraft(String plate) {
        java.util.Set<String> values=new java.util.TreeSet<>(prefs.getStringSet("plateDrafts",java.util.Collections.emptySet()));
        values.add(plate);prefs.edit().putStringSet("plateDrafts",values).apply();
    }
    java.util.Set<String> plateDrafts(){return new java.util.TreeSet<>(prefs.getStringSet("plateDrafts",java.util.Collections.emptySet()));}
    void removePlateDraft(String plate){java.util.Set<String> values=plateDrafts();values.remove(plate);prefs.edit().putStringSet("plateDrafts",values).apply();}
    String deviceId() {
        String id = prefs.getString("installation", "");
        if (id.isEmpty()) { id = UUID.randomUUID().toString(); prefs.edit().putString("installation",id).apply(); }
        return id;
    }
    boolean onboarded() { return prefs.getBoolean("onboarded",false); }
    void onboard() { prefs.edit().putBoolean("onboarded",true).apply(); }
    /** 舊版後端冇 mine 欄位時，用本機記錄判斷邊啲訊息係自己發出 */
    void markSent(String id) {
        if (id == null || id.isEmpty()) return;
        remember("messages",id);
    }
    boolean sentByMe(String id) { return id != null && !id.isEmpty() && remembered("messages",id); }
}
