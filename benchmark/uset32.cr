require "benchmark"
require "../src/permafrost"

xs_r = (0u32...100_000u32).to_a.shuffle!
xs_uset = xs_r.to_pf_uset32
xs_set = xs_r.to_set

ys_r = (0u32...20_000u32).to_a.shuffle!
ys_uset = ys_r.to_pf_uset32
ys_set = ys_r.to_set

# Some shared with xs, others not.
zs_r = (80_000u32...150_000u32).to_a.shuffle!
zs_uset = zs_r.to_pf_uset32
zs_set = zs_r.to_a.shuffle!.to_set

ps_r = (130_000u32...190_000u32).to_a.shuffle!
ps_uset = ps_r.to_pf_uset32
ps_set = ps_r.to_a.shuffle!.to_set

puts "xs.size = #{xs_r.size.humanize}"
puts "ys.size = #{ys_r.size.humanize}"
puts "zs.size = #{zs_r.size.humanize}"
puts "ps.size = #{ps_r.size.humanize}"

Benchmark.ips do |x|
  x.report("USet32: create 100k") { xs_r.to_pf_uset32 }
  x.report("Set: create 100k") { xs_r.to_set }
end

Benchmark.ips do |x|
  x.report("USet32: subset ys xs") { ys_uset.subset_of?(xs_uset) }
  x.report("Set: subset ys xs") { ys_set.subset_of?(xs_set) }
end

Benchmark.ips do |x|
  x.report("USet32: xs union zs") { xs_uset | zs_uset }
  x.report("Set: xs union zs") { xs_set | zs_set }
end

Benchmark.ips do |x|
  x.report("USet32: union subset xs ys") { xs_uset | ys_uset }
  x.report("Set: union subset xs ys") { xs_set | ys_set }
end

Benchmark.ips do |x|
  x.report("USet32: xs intersects? zs (true)") { xs_uset.intersects?(zs_uset) }
  x.report("Set: xs intersects? zs (true)") { xs_set.intersects?(zs_set) }
end

Benchmark.ips do |x|
  x.report("USet32: xs intersects? ps (false)") { xs_uset.intersects?(ps_uset) }
  x.report("Set: xs intersects? ps (false)") { xs_set.intersects?(ps_set) }
end

Benchmark.ips do |x|
  x.report("USet32: xs intersect zs") { xs_uset & zs_uset }
  x.report("Set: xs intersect zs") { xs_set & zs_set }
end

Benchmark.ips do |x|
  x.report("USet32: xs difference zs") { xs_uset - zs_uset }
  x.report("Set: xs difference zs") { xs_set - zs_set }
end

Benchmark.ips do |x|
  x.report("USet32: Jaccard xs zs") { (xs_uset & zs_uset).size / (xs_uset | zs_uset).size }
  x.report("Set: Jaccard xs zs") { (xs_set & zs_set).size / (xs_set | zs_set).size }
end
