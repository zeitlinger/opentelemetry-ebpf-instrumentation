/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

package io.opentelemetry.obi.java.ebpf;

import io.opentelemetry.obi.java.Agent;

/** Test-only bridge for the hard-coded Java method span prototype. */
public final class JavaMethodSpanContext {
  private static final int PACKET_SIZE = 1 + Integer.BYTES + 1;
  private static final ThreadLocal<NativeMemory> PACKET =
      ThreadLocal.withInitial(() -> new NativeMemory(PACKET_SIZE));

  private JavaMethodSpanContext() {}

  public static void enter(int methodId) {
    if (!ThreadInfo.onVirtualThread()) {
      emit(OperationType.JAVA_METHOD_ENTER, methodId, false);
    }
  }

  public static void exit(int methodId, boolean exceptional) {
    if (!ThreadInfo.onVirtualThread()) {
      emit(OperationType.JAVA_METHOD_EXIT, methodId, exceptional);
    }
  }

  private static void emit(OperationType operation, int methodId, boolean exceptional) {
    NativeMemory packet = PACKET.get();
    packet.setByte(0, operation.code);
    packet.setInt(1, methodId);
    packet.setByte(1 + Integer.BYTES, (byte) (exceptional ? 1 : 0));
    Agent.NativeLib.ioctl(0, Agent.IOCTL_CMD, packet.getAddress());
  }
}
