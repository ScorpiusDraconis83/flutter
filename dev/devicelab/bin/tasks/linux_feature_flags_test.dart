// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_devicelab/framework/devices.dart';
import 'package:flutter_devicelab/framework/framework.dart';
import 'package:flutter_devicelab/tasks/integration_tests.dart';

/// Verify that feature flags work on Linux.
Future<void> main() async {
  deviceOperatingSystem = DeviceOperatingSystem.linux;
  await task(featureFlagsTask());
}
