// Lumtub: per-frame timings for the log, read and reset together.

#ifndef FRAME_STATS_H_
#define FRAME_STATS_H_

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <string>

class FrameTiming {
 public:
  void Add(std::chrono::steady_clock::duration took) {
    auto us = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(took).count());
    count_++;
    total_us_ += us;
    auto max = max_us_.load();
    while (us > max && !max_us_.compare_exchange_weak(max, us)) {
    }
  }

  // "name=count/average ms/max ms", then starts again.
  std::string Take(const char* name) {
    auto count = count_.exchange(0);
    auto total = total_us_.exchange(0);
    auto max = max_us_.exchange(0);
    char text[96];
    snprintf(text, sizeof(text), "%s=%llu/%.1fms/%.1fms", name,
             static_cast<unsigned long long>(count),
             count ? total / 1000.0 / count : 0.0, max / 1000.0);
    return text;
  }

 private:
  std::atomic<uint64_t> count_{0};
  std::atomic<uint64_t> total_us_{0};
  std::atomic<uint64_t> max_us_{0};
};

#endif  // FRAME_STATS_H_
