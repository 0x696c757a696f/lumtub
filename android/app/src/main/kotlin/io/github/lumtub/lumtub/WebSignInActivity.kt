package io.github.lumtub.lumtub

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.view.WindowInsets
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import java.io.File

/**
 * Google's sign-in to YouTube in a page of Lumtub's own, for the cookies
 * members-only videos need: on Android no other app's cookies can be read.
 * Only the sign-in is shown here; nothing is played in it. Once YouTube
 * shows signed in, the youtube.com cookies go to a file only this app can
 * read (the core takes them and wipes it), and every cookie and bit of
 * storage the page left is deleted.
 */
class WebSignInActivity : Activity() {
    private var web: WebView? = null
    private var done = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // One an earlier sign-in left when the app was closed under it.
        File(noBackupFilesDir, FILE).delete()
        val web = WebView(this)
        this.web = web
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        // Google turns away pages that call themselves an app's web view;
        // this one is only the sign-in, as in the phone's own browser.
        web.settings.userAgentString = web.settings.userAgentString.replace("; wv", "")
        CookieManager.getInstance().setAcceptCookie(true)
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val scheme = request?.url?.scheme ?: return true
                return scheme != "https" && scheme != "http"
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                if (url != null) check(url)
            }
        }
        val root = FrameLayout(this)
        // No white flash in dark mode before Google's page draws.
        val night = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        root.setBackgroundColor(if (night) Color.BLACK else Color.WHITE)
        web.setBackgroundColor(if (night) Color.BLACK else Color.WHITE)
        root.addView(web, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            } else {
                @Suppress("DEPRECATION")
                view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            }
            insets
        }
        setContentView(root)
        // Cookies are removed in the background; the page opens only once
        // an earlier account's are gone.
        forget {
            if (!isDestroyed && this.web === web) web.loadUrl(SIGN_IN)
        }
    }

    /** Takes the cookies once YouTube shows the account signed in. */
    private fun check(url: String) {
        if (done) return
        val host = Uri.parse(url).host ?: return
        if (host != "youtube.com" && !host.endsWith(".youtube.com")) return
        val cookies = CookieManager.getInstance().getCookie("https://www.youtube.com") ?: return
        val names = cookies.split(';').map { it.substringBefore('=').trim() }.toSet()
        if ("SAPISID" !in names && "__Secure-3PAPISID" !in names) return
        done = true
        val file = File(noBackupFilesDir, FILE)
        file.writeText(cookies)
        file.setReadable(false, false)
        file.setReadable(true, true)
        setResult(RESULT_OK, Intent().putExtra(PATH, file.absolutePath))
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        val web = web
        if (web != null && web.canGoBack()) web.goBack() else super.onBackPressed()
    }

    override fun onDestroy() {
        web?.apply {
            stopLoading()
            clearHistory()
            clearCache(true)
            destroy()
        }
        web = null
        forget()
        super.onDestroy()
    }

    /** Deletes every cookie and bit of storage a sign-in page left, then runs [then]. */
    private fun forget(then: (() -> Unit)? = null) {
        WebStorage.getInstance().deleteAllData()
        val cookies = CookieManager.getInstance()
        cookies.removeAllCookies {
            cookies.flush()
            then?.invoke()
        }
    }

    companion object {
        const val PATH = "path"
        private const val FILE = "web-sign-in.txt"

        private const val SIGN_IN = "https://accounts.google.com/ServiceLogin?service=youtube&passive=true" +
            "&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26next%3Dhttps%253A%252F%252Fm.youtube.com%252F"
    }
}
