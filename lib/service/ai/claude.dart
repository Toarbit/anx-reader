import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio_intercept_to_curl/dio_intercept_to_curl.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:pretty_dio_logger/pretty_dio_logger.dart';

Stream<String> claudeGenerateStream(
  String prompt,
  Map<String, String> config,
) async* {
  final url = config['url'];
  final apiKey = config['api_key'];
  final model = config['model'];
  final dio = Dio();

  dio.interceptors.add(PrettyDioLogger(
    requestHeader: true,
    requestBody: true,
    responseBody: true,
    responseHeader: false,
    error: true,
    compact: true,
    maxWidth: 90,
    enabled: kDebugMode,
  ));
  dio.interceptors.add(DioInterceptToCurl(printOnSuccess: true));

  try {
    final response = await dio.post(
      url!,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        responseType: ResponseType.stream,
        validateStatus: (status) => true,
      ),
      data: {
        'model': model,
        'max_tokens': 2048,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'stream': true,
      },
    );

    final stream = response.data.stream;
    await for (final chunk in stream.transform(
      StreamTransformer<Uint8List, String>.fromHandlers(
        handleData: (Uint8List data, EventSink<String> sink) {
          sink.add(utf8.decode(data));
        },
      ),
    )) {
      for (final line in chunk.split('\n')) {
        if (line.isEmpty || line.startsWith('event: ')) continue;
        final data = line.startsWith('data: ') ? line.substring(6) : line;
        try {
          final json = jsonDecode(data);

          if (json['type'] == 'content_block_delta') {
            final text = json['delta']['text'];
            if (text != null && text.isNotEmpty) {
              yield text;
            }
          }
        } catch (e) {
          yield* Stream.error('Parse error: $e\nData: $data');
          continue;
        }
      }
    }
  } catch (e) {
    if (kDebugMode) {
      throw Exception(e);
    } else {
      yield* Stream.error('Request failed: $e');
    }
  } finally {
    dio.close();
  }
}
