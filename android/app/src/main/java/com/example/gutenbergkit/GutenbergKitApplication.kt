package com.example.gutenbergkit

import android.app.Application
import rs.wordpress.api.android.KeystorePasswordTransformer
import uniffi.wp_mobile.AccountRepository

class GutenbergKitApplication : Application() {
    lateinit var accountRepository: AccountRepository
        private set

    override fun onCreate() {
        super.onCreate()
        accountRepository = AccountRepository(
            rootPath = filesDir.resolve("accounts").absolutePath,
            passwordTransformer = KeystorePasswordTransformer()
        )
    }
}
