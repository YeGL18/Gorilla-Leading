package com.gorilla.leading;

import org.junit.Test;
import static org.junit.Assert.*;

public class ReplyDraftTest {
    @Test public void retryKeepsKeyUntilContentChanges() {
        ReplyDraft draft = new ReplyDraft();
        draft.text = "多謝提醒";
        String first = draft.beginAttempt(draft.text);
        assertEquals(first, draft.beginAttempt(draft.text));
        draft.text = "唔該，已處理";
        assertNotEquals(first, draft.beginAttempt(draft.text));
    }

    @Test public void successfulSendStartsANewAttempt() {
        ReplyDraft draft = new ReplyDraft();
        String first = draft.beginAttempt("唔該");
        draft.sent();
        assertEquals("", draft.text);
        assertNotEquals(first, draft.beginAttempt("唔該"));
    }
}
