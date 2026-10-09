package com.goldtraderpro233

import android.app.Activity
import android.os.Bundle
import android.widget.Toast

/** UI-only prototype. Trading buttons intentionally remain disabled until an authenticated backend exists. */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        Toast.makeText(this, "Prototype only — no broker connection", Toast.LENGTH_LONG).show()
    }
}
