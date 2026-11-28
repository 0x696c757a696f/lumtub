import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/jobs.dart';

void main() {
  test('a lane runs as many jobs at once as it allows, the most urgent first', () async {
    final queue = JobQueue();
    addTearDown(queue.dispose);
    final gates = {for (final k in ['a', 'b', 'c']) k: Completer<void>()};
    final started = <String>[];
    Future<String> job(String key, JobPriority priority) => queue.run(key, (context) async {
          started.add(key);
          await gates[key]!.future;
          return key;
        }, lane: JobLane.heavy, priority: priority);
    final a = job('a', JobPriority.background);
    final b = job('b', JobPriority.background);
    final c = job('c', JobPriority.watching);
    await pumpEventQueue();
    expect(started, ['a']);
    expect(queue.jobs.map((j) => (j.key, j.running)), [('a', true), ('b', false), ('c', false)]);
    gates['a']!.complete();
    expect(await a, 'a');
    await pumpEventQueue();
    expect(started, ['a', 'c']);
    gates['c']!.complete();
    gates['b']!.complete();
    expect(await c, 'c');
    expect(await b, 'b');
    expect(queue.jobs, isEmpty);
  });

  test('asking for a job already queued joins it', () async {
    final queue = JobQueue();
    addTearDown(queue.dispose);
    var runs = 0;
    final gate = Completer<void>();
    Future<int> job() => queue.run('speech:v1', (context) async {
          runs++;
          await gate.future;
          return 7;
        });
    final first = job();
    final second = job();
    gate.complete();
    expect(await first, 7);
    expect(await second, 7);
    expect(runs, 1);
  });

  test('background jobs wait while paused; others do not', () async {
    var paused = true;
    final queue = JobQueue(backgroundPaused: () => paused);
    addTearDown(queue.dispose);
    final ran = <String>[];
    final later = queue.run('index', (context) async => ran.add('index'), lane: JobLane.light, priority: JobPriority.background);
    await queue.run('asked', (context) async => ran.add('asked'), lane: JobLane.light);
    await pumpEventQueue();
    expect(ran, ['asked']);
    paused = false;
    queue.wake();
    await later;
    expect(ran, ['asked', 'index']);
  });

  test('a waiting job can be cancelled and a running one is told to stop', () async {
    final queue = JobQueue();
    addTearDown(queue.dispose);
    final gate = Completer<void>();
    final running = queue.run('one', (context) async {
      await gate.future;
      context.checkCancelled();
      return 1;
    }, lane: JobLane.heavy);
    final waiting = queue.run('two', (context) async => 2, lane: JobLane.heavy);
    await pumpEventQueue();
    queue.cancel('two');
    queue.cancel('one');
    gate.complete();
    await expectLater(waiting, throwsA(isA<JobCancelled>()));
    await expectLater(running, throwsA(isA<JobCancelled>()));
  });

  test('asking again for a job told to stop starts it afresh', () async {
    final queue = JobQueue();
    addTearDown(queue.dispose);
    final gate = Completer<void>();
    final first = queue.run('one', (context) async {
      await gate.future;
      context.checkCancelled();
      return 1;
    });
    await pumpEventQueue();
    queue.cancel('one');
    final again = queue.run('one', (context) async => 2);
    gate.complete();
    await expectLater(first, throwsA(isA<JobCancelled>()));
    expect(await again, 2);
  });

  test('progress shows on the job and failures reach the caller', () async {
    final queue = JobQueue();
    addTearDown(queue.dispose);
    final gate = Completer<void>();
    final job = queue.run('p', (context) async {
      context.progress('Recognizing', 1, 3);
      await gate.future;
      throw StateError('broken');
    });
    await pumpEventQueue();
    expect(queue.job('p')!.stage, 'Recognizing');
    expect(queue.job('p')!.done, 1);
    gate.complete();
    await expectLater(job, throwsStateError);
    expect(queue.job('p'), isNull);
  });
}
