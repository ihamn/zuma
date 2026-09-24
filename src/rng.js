// 确定性随机数：同 seed 必产出同序列（单元测试、回放、关卡复现都依赖它）

export function makeRng(seed) {
  let a = (seed >>> 0) || 0x9e3779b9;
  const rng = function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  rng.int = function (n) { return Math.floor(rng() * n); };
  rng.pick = function (arr) { return arr[rng.int(arr.length)]; };
  rng.seed = seed >>> 0;
  return rng;
}

