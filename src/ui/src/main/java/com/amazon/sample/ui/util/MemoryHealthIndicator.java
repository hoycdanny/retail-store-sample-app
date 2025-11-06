package com.amazon.sample.ui.util;

import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.stereotype.Component;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryUsage;

@Component
public class MemoryHealthIndicator implements HealthIndicator {

    private static final double MEMORY_THRESHOLD = 0.85; // 85% threshold

    @Override
    public Health health() {
        try {
            MemoryMXBean memoryBean = ManagementFactory.getMemoryMXBean();
            MemoryUsage heapMemoryUsage = memoryBean.getHeapMemoryUsage();
            MemoryUsage nonHeapMemoryUsage = memoryBean.getNonHeapMemoryUsage();

            long heapUsed = heapMemoryUsage.getUsed();
            long heapMax = heapMemoryUsage.getMax();
            long nonHeapUsed = nonHeapMemoryUsage.getUsed();
            long nonHeapMax = nonHeapMemoryUsage.getMax();

            double heapUsagePercent = (double) heapUsed / heapMax;
            double nonHeapUsagePercent = nonHeapMax > 0 ? (double) nonHeapUsed / nonHeapMax : 0;

            Health.Builder healthBuilder = heapUsagePercent < MEMORY_THRESHOLD ? 
                Health.up() : Health.down();

            return healthBuilder
                .withDetail("heap.used", formatBytes(heapUsed))
                .withDetail("heap.max", formatBytes(heapMax))
                .withDetail("heap.usage", String.format("%.2f%%", heapUsagePercent * 100))
                .withDetail("nonHeap.used", formatBytes(nonHeapUsed))
                .withDetail("nonHeap.max", nonHeapMax > 0 ? formatBytes(nonHeapMax) : "unlimited")
                .withDetail("nonHeap.usage", String.format("%.2f%%", nonHeapUsagePercent * 100))
                .withDetail("threshold", String.format("%.0f%%", MEMORY_THRESHOLD * 100))
                .withDetail("status", heapUsagePercent < MEMORY_THRESHOLD ? "healthy" : "critical")
                .build();

        } catch (Exception e) {
            return Health.down()
                .withDetail("error", "Failed to retrieve memory information")
                .withDetail("exception", e.getMessage())
                .build();
        }
    }

    private String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        int exp = (int) (Math.log(bytes) / Math.log(1024));
        String pre = "KMGTPE".charAt(exp - 1) + "";
        return String.format("%.1f %sB", bytes / Math.pow(1024, exp), pre);
    }
}