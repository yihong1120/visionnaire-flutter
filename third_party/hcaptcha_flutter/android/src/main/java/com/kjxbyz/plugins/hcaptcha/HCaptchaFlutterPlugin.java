package com.kjxbyz.plugins.hcaptcha;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.VisibleForTesting;
import androidx.fragment.app.FragmentActivity;

import com.hcaptcha.sdk.HCaptcha;
import com.hcaptcha.sdk.HCaptchaConfig;
import com.hcaptcha.sdk.HCaptchaError;
import com.hcaptcha.sdk.HCaptchaSize;

import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class HCaptchaFlutterPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
  private static final String CHANNEL_NAME = "plugins.kjxbyz.com/hcaptcha_flutter_plugin";
  private static final String METHOD_SHOW = "show";
  private static final String METHOD_DISMISS = "dismiss";

  private MethodChannel channel;
  private HCaptchaDelegate delegate;

  @VisibleForTesting
  public void initInstance(BinaryMessenger messenger) {
    channel = new MethodChannel(messenger, CHANNEL_NAME);
    delegate = new HCaptchaDelegate();
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
    initInstance(binding.getBinaryMessenger());
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    dispose();
  }

  @Override
  public void onAttachedToActivity(ActivityPluginBinding binding) {
    delegate.setActivity(binding.getActivity());
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    disposeActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
    delegate.setActivity(binding.getActivity());
  }

  @Override
  public void onDetachedFromActivity() {
    disposeActivity();
  }

  private void disposeActivity() {
    if (delegate == null) {
      return;
    }
    delegate.dismiss();
    delegate.setActivity(null);
  }

  private void dispose() {
    if (delegate != null) {
      delegate.dismiss();
      delegate = null;
    }
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    if (delegate == null) {
      result.error("plugin_detached", "The hCaptcha plugin is not attached.", null);
      return;
    }

    switch (call.method) {
      case METHOD_SHOW:
        handleShow(call.arguments, result);
        break;
      case METHOD_DISMISS:
        delegate.dismiss();
        result.success(null);
        break;
      default:
        result.notImplemented();
    }
  }

  private void handleShow(Object arguments, MethodChannel.Result result) {
    if (!(arguments instanceof Map)) {
      result.error("invalid_arguments", "hCaptcha configuration must be a map.", null);
      return;
    }

    Map<?, ?> config = (Map<?, ?>) arguments;
    Object siteKeyValue = config.get("siteKey");
    Object languageValue = config.get("language");
    if (!(siteKeyValue instanceof String) || ((String) siteKeyValue).trim().isEmpty()) {
      result.error("invalid_arguments", "A non-empty hCaptcha site key is required.", null);
      return;
    }
    if (!(languageValue instanceof String) || ((String) languageValue).trim().isEmpty()) {
      result.error("invalid_arguments", "A non-empty hCaptcha language is required.", null);
      return;
    }

    delegate.show(
        ((String) siteKeyValue).trim(),
        ((String) languageValue).trim(),
        result
    );
  }

  static final class HCaptchaDelegate {
    private static final String TAG = "HCaptchaDelegate";

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private Activity activity;
    private HCaptcha hCaptcha;
    private MethodChannel.Result pendingResult;
    private long challengeGeneration;

    void setActivity(Activity activity) {
      this.activity = activity;
    }

    void show(String siteKey, String language, MethodChannel.Result result) {
      if (pendingResult != null) {
        result.error("challenge_in_progress", "An hCaptcha challenge is already open.", null);
        return;
      }
      if (!(activity instanceof FragmentActivity)) {
        result.error(
            "presentation_unavailable",
            "hCaptcha requires an attached FragmentActivity.",
            null
        );
        return;
      }

      final long generation = ++challengeGeneration;
      pendingResult = result;

      try {
        hCaptcha = HCaptcha.getClient((FragmentActivity) activity)
            .verifyWithHCaptcha(createConfig(siteKey, language));
        hCaptcha
            .addOnSuccessListener(response -> {
              final String token = response.getTokenResult();
              mainHandler.post(() -> finishSuccess(generation, token));
            })
            .addOnFailureListener(error -> {
              final String code = String.valueOf(error.getStatusCode());
              final String message = error.getMessage();
              mainHandler.post(() -> finishError(generation, code, message));
            });
      } catch (RuntimeException error) {
        Log.e(TAG, "Unable to start hCaptcha.", error);
        finishError(generation, "challenge_start_failed", error.getMessage());
      }
    }

    void dismiss() {
      MethodChannel.Result result = pendingResult;
      pendingResult = null;
      tearDownChallenge();
      if (result != null) {
        result.error(
            "challenge_cancelled",
            "hCaptcha challenge was cancelled.",
            null
        );
      }
    }

    private void finishSuccess(long generation, String token) {
      if (!isCurrent(generation)) {
        return;
      }
      if (token == null || token.trim().isEmpty()) {
        finishError(generation, "invalid_response", "hCaptcha returned an empty token.");
        return;
      }

      MethodChannel.Result result = pendingResult;
      pendingResult = null;
      tearDownChallenge();
      result.success(token.trim());
    }

    private void finishError(long generation, String code, String message) {
      if (!isCurrent(generation)) {
        return;
      }

      MethodChannel.Result result = pendingResult;
      pendingResult = null;
      tearDownChallenge();
      result.error(
          code == null || code.isEmpty() ? "hcaptcha_failed" : code,
          message == null || message.isEmpty() ? "hCaptcha challenge failed." : message,
          null
      );
    }

    private boolean isCurrent(long generation) {
      return pendingResult != null && challengeGeneration == generation;
    }

    private void tearDownChallenge() {
      challengeGeneration += 1;
      HCaptcha challenge = hCaptcha;
      hCaptcha = null;
      if (challenge == null) {
        return;
      }
      try {
        challenge.reset();
      } catch (RuntimeException error) {
        Log.w(TAG, "Unable to reset hCaptcha during cleanup.", error);
      }
    }

    private HCaptchaConfig createConfig(String siteKey, String locale) {
      return HCaptchaConfig.builder()
          .siteKey(siteKey)
          .locale(locale)
          .size(HCaptchaSize.INVISIBLE)
          .loading(true)
          .hideDialog(false)
          .disableHardwareAcceleration(true)
          .tokenExpiration(10)
          .diagnosticLog(false)
          .retryPredicate(
              (config, exception) -> exception.getHCaptchaError() == HCaptchaError.SESSION_TIMEOUT
          )
          .build();
    }
  }
}
