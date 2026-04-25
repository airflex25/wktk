package com.wktk.audio

import android.content.Context
import android.media.AudioManager

/**
 * 워키토키스러운 음성 라우팅 도우미.
 *  - VOICE_COMMUNICATION 모드: 에코 캔슬러/노이즈 서프레서가 활성화되는 모드.
 *  - 스피커폰 ON: 폰을 들지 않아도 들리도록 (실제 워키토키 UX).
 */
class AudioRouter(context: Context) {
    private val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    fun enterCallMode(speakerOn: Boolean = true) {
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        am.isSpeakerphoneOn = speakerOn
    }

    fun exitCallMode() {
        am.isSpeakerphoneOn = false
        am.mode = AudioManager.MODE_NORMAL
    }
}
