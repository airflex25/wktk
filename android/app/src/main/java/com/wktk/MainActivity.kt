package com.wktk

import android.Manifest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.wktk.ui.WktkApp
import com.wktk.ui.WktkViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 마이크 권한이 없으면 시작 시 한 번 요청한다.
        val launcher = registerForActivityResult(
            ActivityResultContracts.RequestPermission()
        ) { /* 결과는 ViewModel이 다시 권한을 검사하므로 무시 */ }

        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO)
            != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            launcher.launch(Manifest.permission.RECORD_AUDIO)
        }

        setContent {
            val vm: WktkViewModel = viewModel()
            val state by vm.state.collectAsState()
            WktkApp(state = state, onIntent = vm::onIntent)
        }
    }
}
