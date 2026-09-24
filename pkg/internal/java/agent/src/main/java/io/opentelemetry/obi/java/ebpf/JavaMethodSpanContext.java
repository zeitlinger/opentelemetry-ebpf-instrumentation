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

  /** Scratch proof: snapshot the active native method stack for a submitted task. */
  public static void captureTask(int taskId) {
    if (!ThreadInfo.onVirtualThread()) {
      emitTask(OperationType.JAVA_METHOD_TASK_CAPTURE, taskId);
    }
  }

  /** Scratch proof: install a captured method stack on the task worker. */
  public static void enterTask(int taskId) {
    if (!ThreadInfo.onVirtualThread()) {
      emitTask(OperationType.JAVA_METHOD_TASK_ENTER, taskId);
    }
  }

  /** Scratch proof: restore the task worker's prior method stack. */
  public static void exitTask(int taskId) {
    if (!ThreadInfo.onVirtualThread()) {
      emitTask(OperationType.JAVA_METHOD_TASK_EXIT, taskId);
    }
  }

  private static void emitTask(OperationType operation, int taskId) {
    NativeMemory packet = PACKET.get();
    packet.setByte(0, operation.code);
    packet.setInt(1, taskId);
    Agent.NativeLib.ioctl(0, Agent.IOCTL_CMD, packet.getAddress());
  }

  private static void emit(OperationType operation, int methodId, boolean exceptional) {
    NativeMemory packet = PACKET.get();
    packet.setByte(0, operation.code);
    packet.setInt(1, methodId);
    packet.setByte(1 + Integer.BYTES, (byte) (exceptional ? 1 : 0));
    Agent.NativeLib.ioctl(0, Agent.IOCTL_CMD, packet.getAddress());
  }
}
