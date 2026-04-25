package com.wktk.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ── 색상 상수 ────────────────────────────────────────────────────
private val ColorBackground = Color(0xFF121212)
private val ColorSurface    = Color(0xFF1E1E1E)
private val ColorPrimary    = Color(0xFF4CAF50)
private val ColorOnSurface  = Color(0xFFE0E0E0)
private val ColorPttActive  = Color(0xFFE53935)
private val ColorPttIdle    = Color(0xFF455A64)
private val ColorError      = Color(0xFFCF6679)
private val ColorSubtle     = Color(0xFF757575)

private val WktkColorScheme = darkColorScheme(
    primary          = ColorPrimary,
    background       = ColorBackground,
    surface          = ColorSurface,
    onBackground     = ColorOnSurface,
    onSurface        = ColorOnSurface,
    error            = ColorError,
)

// ── 최상위 진입점 ─────────────────────────────────────────────────
@Composable
fun WktkApp(state: WktkState, onIntent: (WktkIntent) -> Unit) {
    MaterialTheme(colorScheme = WktkColorScheme) {
        Surface(modifier = Modifier.fillMaxSize(), color = ColorBackground) {
            if (state.joinedKey == null) KeyEntryScreen(state, onIntent)
            else RoomScreen(state, onIntent)
        }
    }
}

// ── 키 입력 화면 ──────────────────────────────────────────────────
@Composable
private fun KeyEntryScreen(state: WktkState, onIntent: (WktkIntent) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // 앱 타이틀
        Text(
            text = "📡 WKTK",
            style = MaterialTheme.typography.displaySmall.copy(
                fontWeight = FontWeight.Black,
                letterSpacing = 6.sp,
            ),
            color = ColorPrimary,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            text = "워키토키",
            style = MaterialTheme.typography.bodyMedium,
            color = ColorSubtle,
        )

        Spacer(Modifier.height(40.dp))

        // 6자리 키 입력
        OutlinedTextField(
            value = state.keyInput,
            onValueChange = { v ->
                if (v.length <= 6 && v.all(Char::isDigit))
                    onIntent(WktkIntent.UpdateKeyInput(v))
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            label = { Text("주파수 키 (6자리)") },
            placeholder = { Text("000000") },
            textStyle = MaterialTheme.typography.headlineMedium.copy(
                fontFamily = FontFamily.Monospace,
                textAlign = TextAlign.Center,
                letterSpacing = 8.sp,
            ),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = ColorPrimary,
                focusedLabelColor  = ColorPrimary,
                cursorColor        = ColorPrimary,
                unfocusedBorderColor = ColorSubtle,
                unfocusedLabelColor  = ColorSubtle,
            ),
        )

        // 에러 메시지
        state.error?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, color = ColorError, style = MaterialTheme.typography.bodySmall)
        }

        Spacer(Modifier.height(24.dp))

        // 버튼 행
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                onClick = { onIntent(WktkIntent.RequestRandomKey) },
                colors = ButtonDefaults.buttonColors(containerColor = ColorSurface),
            ) {
                Text("새 키 받기", color = ColorOnSurface)
            }
            Button(
                onClick = { onIntent(WktkIntent.JoinKey) },
                colors = ButtonDefaults.buttonColors(containerColor = ColorPrimary),
                enabled = state.keyInput.length == 6,
            ) {
                Text("입장", color = Color.White, fontWeight = FontWeight.Bold)
            }
        }

        Spacer(Modifier.height(32.dp))

        // 서버 연결 상태
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val dotColor = if (state.connected) ColorPrimary else ColorSubtle
            Box(
                Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(dotColor)
            )
            Text(
                text = if (state.connected) "서버 연결됨" else "서버 연결 중…",
                style = MaterialTheme.typography.bodySmall,
                color = if (state.connected) ColorPrimary else ColorSubtle,
            )
        }
    }
}

// ── 룸 화면 ───────────────────────────────────────────────────────
@Composable
private fun RoomScreen(state: WktkState, onIntent: (WktkIntent) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // 상단: 키 + 접속자 수
        Text(
            text = "주파수",
            style = MaterialTheme.typography.labelLarge,
            color = ColorSubtle,
        )
        Text(
            text = state.joinedKey ?: "",
            style = MaterialTheme.typography.displayMedium.copy(
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Black,
                letterSpacing = 10.sp,
            ),
            color = ColorPrimary,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            text = if (state.peers.isEmpty()) "대기 중…" else "연결된 사람: ${state.peers.size}명",
            style = MaterialTheme.typography.bodyMedium,
            color = if (state.peers.isEmpty()) ColorSubtle else ColorOnSurface,
        )

        Spacer(Modifier.height(32.dp))

        // VOX 토글
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "PTT",
                style = MaterialTheme.typography.labelLarge,
                color = if (state.mode == TalkMode.PTT) ColorOnSurface else ColorSubtle,
            )
            Switch(
                checked = state.mode == TalkMode.VOX,
                onCheckedChange = { on ->
                    onIntent(WktkIntent.SetMode(if (on) TalkMode.VOX else TalkMode.PTT))
                },
                colors = SwitchDefaults.colors(
                    checkedThumbColor   = ColorPrimary,
                    checkedTrackColor   = ColorPrimary.copy(alpha = 0.3f),
                    uncheckedThumbColor = ColorSubtle,
                ),
            )
            Text(
                text = "VOX",
                style = MaterialTheme.typography.labelLarge,
                color = if (state.mode == TalkMode.VOX) ColorPrimary else ColorSubtle,
            )
        }

        Spacer(Modifier.weight(1f))

        // PTT 버튼 (메인)
        PttButton(
            transmitting = state.transmitting || state.mode == TalkMode.VOX,
            enabled = state.mode == TalkMode.PTT,
            onPress   = { onIntent(WktkIntent.PttPress) },
            onRelease = { onIntent(WktkIntent.PttRelease) },
        )

        Spacer(Modifier.weight(1f))

        // 나가기
        Button(
            onClick = { onIntent(WktkIntent.LeaveKey) },
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF37474F)),
        ) {
            Text("나가기", color = ColorOnSurface)
        }
    }
}

// ── PTT 원형 버튼 ─────────────────────────────────────────────────
@Composable
private fun PttButton(
    transmitting: Boolean,
    enabled: Boolean,
    onPress: () -> Unit,
    onRelease: () -> Unit,
) {
    val bgColor by animateColorAsState(
        targetValue = if (transmitting) ColorPttActive else ColorPttIdle,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "ptt_color",
    )
    val borderColor = if (transmitting) ColorPttActive.copy(alpha = 0.4f)
                      else Color.White.copy(alpha = 0.08f)

    Box(
        modifier = Modifier
            .size(220.dp)
            .shadow(if (transmitting) 24.dp else 4.dp, CircleShape)
            .clip(CircleShape)
            .background(bgColor)
            .border(2.dp, borderColor, CircleShape)
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                detectTapGestures(
                    onPress = {
                        onPress()
                        try { tryAwaitRelease() } finally { onRelease() }
                    }
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = when {
                    transmitting && enabled -> "●"
                    transmitting            -> "●"
                    else                    -> "○"
                },
                fontSize = 36.sp,
                color = Color.White.copy(alpha = 0.9f),
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = when {
                    transmitting && enabled -> "TALKING"
                    transmitting            -> "VOX ON"
                    enabled                 -> "PUSH TO TALK"
                    else                    -> "VOX STANDBY"
                },
                style = MaterialTheme.typography.labelLarge.copy(
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 2.sp,
                ),
                color = Color.White,
            )
        }
    }
}
