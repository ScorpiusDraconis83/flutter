// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/source.dart';

import 'dependency_graph.dart';

extension TokenExtension on Token {
  /// Convenience getter to identify tokens for private fields and functions.
  bool get isPrivate => toString().startsWith('_');

  /// Convenience getter to identify WidgetBuilder types.
  bool get isWidgetBuilder => toString() == 'WidgetBuilder';
}

extension AnnotationExtension on Annotation {
  static final Uri widgetPreviewsLibraryUri = Uri.parse(
    'package:flutter/src/widget_previews/widget_previews.dart',
  );

  /// Convenience getter to identify `@Preview` annotations
  bool get isPreview =>
      name.name == 'Preview' &&
      elementAnnotation!.element2?.library2!.uri == widgetPreviewsLibraryUri;

  bool get isMultiPreview {
    final Element2? element = elementAnnotation!.element2;
    if (element is ConstructorElement2) {
      final InterfaceType type = element.enclosingElement2.supertype!;
      return type.getDisplayString() == 'MultiPreview' &&
          type.element3.library2.uri == widgetPreviewsLibraryUri;
    }
    return false;
  }

  List<DartObject> findMultiPreviewPreviewNodes({required AnalysisContext context}) {
    final DartObject evaluatedAnnotation = elementAnnotation!.computeConstantValue()!;
    final Element2 element = evaluatedAnnotation.type!.element3!;
    if (element is ClassElement2) {
      final InterfaceType type = element.supertype!;
      if (type.getDisplayString() != 'MultiPreview') {
        throw StateError('$element is not a MultiPreview!');
      }
      final DartObject? previewsField = evaluatedAnnotation.getField('previews');
      return previewsField?.toListValue() ?? <DartObject>[];
    }
    // Invalid preview.
    return <DartObject>[];
  }
}

/// Convenience getters for examining [String] paths.
extension StringExtension on String {
  bool get isDartFile => endsWith('.dart');
  bool get isPubspec => endsWith('pubspec.yaml');
  bool get doesContainDartTool => contains('.dart_tool');
}

extension LibraryElement2Extension on LibraryElement2 {
  /// Convenience method to package path and [uri] into a [PreviewPath]
  PreviewPath toPreviewPath() => (path: firstFragment.source.fullName, uri: uri);
}

extension ParsedUnitResultExtension on ParsedUnitResult {
  /// Convenience method to package [path] and [uri] into a [PreviewPath]
  PreviewPath toPreviewPath() => (path: path, uri: uri);
}

extension SourceExtension on Source {
  /// Convenience method to package [fullName] and [uri] into a [PreviewPath]
  PreviewPath toPreviewPath() => (path: fullName, uri: uri);
}

/// Used to protect global state accessed in blocks containing calls to
/// asynchronous methods.
///
/// Originally from DDS:
/// https://github.com/dart-lang/sdk/blob/3fe58da3cfe2c03fb9ee691a7a4709082fad3e73/pkg/dds/lib/src/utils/mutex.dart
class PreviewDetectorMutex {
  /// Executes a block of code containing asynchronous calls atomically.
  ///
  /// If no other asynchronous context is currently executing within
  /// [criticalSection], it will immediately be called. Otherwise, the
  /// caller will be suspended and entered into a queue to be resumed once the
  /// lock is released.
  Future<T> runGuarded<T>(FutureOr<T> Function() criticalSection) async {
    try {
      await _acquireLock();
      return await criticalSection();
    } finally {
      _releaseLock();
    }
  }

  Future<void> _acquireLock() async {
    if (!_locked) {
      _locked = true;
      return;
    }

    final request = Completer<void>();
    _outstandingRequests.add(request);
    await request.future;
  }

  void _releaseLock() {
    if (_outstandingRequests.isNotEmpty) {
      final Completer<void> request = _outstandingRequests.removeFirst();
      request.complete();
      return;
    }
    // Only release the lock if no other requests are pending to prevent races
    // between the next request from the queue to be handled and incoming
    // requests.
    _locked = false;
  }

  var _locked = false;
  final _outstandingRequests = Queue<Completer<void>>();
}
