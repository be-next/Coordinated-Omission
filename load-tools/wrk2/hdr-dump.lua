-- Dump the full per-request latency distribution at the end of the run,
-- in the same percentile-distribution format that the --latency flag prints
-- to stdout, but written to a file we can post-process.

done = function(summary, latency, requests)
   local f = io.open("wrk2.hdr", "w")
   if f == nil then return end
   f:write("Value(usec)\tPercentile\tTotalCount\t1/(1-Percentile)\n")
   for _, p in ipairs({
      0.0, 0.1, 0.2, 0.3, 0.4, 0.5,
      0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.825, 0.85, 0.875,
      0.9, 0.925, 0.95, 0.975,
      0.99, 0.999, 0.9999, 0.99999, 1.0
   }) do
      local v = latency:percentile(p * 100)
      local pct_str = string.format("%.6f", p)
      f:write(string.format("%d\t%s\t-\t-\n", v, pct_str))
   end
   f:close()
end
