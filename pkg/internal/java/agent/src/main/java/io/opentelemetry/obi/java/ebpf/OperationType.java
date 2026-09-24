/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

package io.opentelemetry.obi.java.ebpf;

public enum OperationType {
  SEND((byte) 1),
  RECEIVE((byte) 2),
  THREAD((byte) 3),
  // virtual thread mounted on the calling carrier; payload = its logical id
  VT_MOUNT((byte) 4),
  // virtual thread unmounted from the calling carrier; payload unused
  VT_UNMOUNT((byte) 5),
  JVM_RUNTIME_SNAPSHOT((byte) 6),
  JVM_GC_DURATION((byte) 7),
  JAVA_METHOD_ENTER((byte) 8),
  JAVA_METHOD_EXIT((byte) 9),
  JAVA_METHOD_TASK_CAPTURE((byte) 10),
  JAVA_METHOD_TASK_ENTER((byte) 11),
  JAVA_METHOD_TASK_EXIT((byte) 12);

  public final byte code;

  OperationType(byte code) {
    this.code = code;
  }
}
