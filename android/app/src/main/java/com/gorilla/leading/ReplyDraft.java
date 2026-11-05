package com.gorilla.leading;

import java.util.UUID;

/** Keep a retry's idempotency key with its draft, even when the screen is rebuilt. */
final class ReplyDraft {
    String text = "";
    private String attempted = "";
    private String key = UUID.randomUUID().toString();

    String beginAttempt(String value) {
        if (!value.equals(attempted)) {
            attempted = value;
            key = UUID.randomUUID().toString();
        }
        return key;
    }

    void sent() {
        text = "";
        attempted = "";
        key = UUID.randomUUID().toString();
    }
}
