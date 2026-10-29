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
    private final String scope;
    Session(Context context) {
        prefs = context.getSharedPreferences("community", Context.MODE_PRIVATE);
        scope = "session:" + BuildConfig.API_BASE_URL;
    }
    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias("gorilla-community")) return (SecretKey)store.getKey("gorilla-community", null);
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder("gorilla-community", KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }
    String token() {
        try {
            String value = prefs.getString(scope, ""); if (value.isEmpty()) return "";
            String[] parts = value.split(":");
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)));
            return new String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), StandardCharsets.UTF_8);
        } catch (Exception e) { clear(); return ""; }
    }
    void save(String token) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        String value = Base64.encodeToString(cipher.getIV(),Base64.NO_WRAP) + ":" + Base64.encodeToString(cipher.doFinal(token.getBytes(StandardCharsets.UTF_8)),Base64.NO_WRAP);
        if (!prefs.edit().putString(scope,value).commit()) throw new Exception("無法安全儲存登入資料");
    }
    void clear() { prefs.edit().remove(scope).apply(); }
    String deviceId() {
        String id = prefs.getString("installation", "");
        if (id.isEmpty()) { id = UUID.randomUUID().toString(); prefs.edit().putString("installation",id).apply(); }
        return id;
    }
    boolean onboarded() { return prefs.getBoolean("onboarded",false); }
    void onboard() { prefs.edit().putBoolean("onboarded",true).apply(); }
}
