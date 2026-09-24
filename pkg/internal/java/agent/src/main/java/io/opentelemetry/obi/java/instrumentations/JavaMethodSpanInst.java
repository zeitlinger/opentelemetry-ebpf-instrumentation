/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

package io.opentelemetry.obi.java.instrumentations;

import io.opentelemetry.obi.java.ebpf.JavaMethodSpanContext;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.matcher.ElementMatcher;
import net.bytebuddy.matcher.ElementMatchers;

/** Hard-coded proof selectors; this is not a supported user configuration API. */
public final class JavaMethodSpanInst {
  private static final String TARGET_CLASS = "io.grafana.checkout.CheckoutService";

  private JavaMethodSpanInst() {}

  public static ElementMatcher<? super TypeDescription> type() {
    return ElementMatchers.named(TARGET_CLASS);
  }

  public static AgentBuilder.Transformer transformer() {
    return (builder, type, classLoader, module, protectionDomain) ->
        builder
            .visit(Advice.to(CheckoutAdvice.class).on(ElementMatchers.named("checkout")))
            .visit(Advice.to(ValidateAdvice.class).on(ElementMatchers.named("validateOrder")));
  }

  public static final class CheckoutAdvice {
    @Advice.OnMethodEnter(suppress = Throwable.class)
    public static void enter() {
      JavaMethodSpanContext.enter(1);
    }

    @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
    public static void exit(@Advice.Thrown Throwable thrown) {
      JavaMethodSpanContext.exit(1, thrown != null);
    }
  }

  public static final class ValidateAdvice {
    @Advice.OnMethodEnter(suppress = Throwable.class)
    public static void enter() {
      JavaMethodSpanContext.enter(2);
    }

    @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
    public static void exit(@Advice.Thrown Throwable thrown) {
      JavaMethodSpanContext.exit(2, thrown != null);
    }
  }
}
