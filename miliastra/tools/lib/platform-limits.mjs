// 千星奇域平台的硬限制（来自官方文档，不是我们猜的）
//
// ★ 为什么把限制做成**代码**而不是文档里的一段话：
//   导出工具必须能**当场拒绝**一份塞不进编辑器的数据。
//   写在文档里的限制，第一次用的人不会去查；写在代码里的，导出时就报错。
//
// 每一条都带出处，改了要能追溯（官方文档标题 + 原文要点）。

export const LIMITS = {
  pathWaypoints: {
    value: 50, unit: '个',
    src: '《编辑项范围限制》',
    note: '单条路径最多 50 个路点。**这是本项目最紧的一条** —— 槽位数超过 50 就得改轨道。'
  },
  paths: { value: 500, unit: '条', src: '《编辑项范围限制》' },
  runtimeEntities: {
    value: 1000, unit: '个', src: '《编辑项范围限制》',
    note: '球 + 弹丸 + 特效一起算。'
  },
  runtimeListElements: {
    value: 1000, unit: '个', src: '《编辑项范围限制》',
    note: '编辑时只有 100 —— 预置的列表别超过 100 项。'
  },
  entityCustomVars: { value: 500, unit: '个', src: '《编辑项范围限制》' },
  structMembers: { value: 50, unit: '个', src: '《编辑项范围限制》' },
  nodeGraphNodes: { value: 3000, unit: '个', src: '《编辑项范围限制》', note: '单张图' },
  allNodeGraphNodes: { value: 100000, unit: '个', src: '《编辑项范围限制》' },
  nodeGraphVars: { value: 100, unit: '个', src: '《编辑项范围限制》', note: '单张图' },
  graphsPerEntity: { value: 10, unit: '张', src: '《编辑项范围限制》' },
  nodeOutLinks: { value: 20, unit: '个', src: '《编辑项范围限制》', note: '节点出引脚后继数' },
  timersPerEntity: { value: 100, unit: '个', src: '《编辑项范围限制》' },
  globalTimers: { value: 50, unit: '个', src: '《编辑项范围限制》' },
  stringLen: { value: 40, unit: '英文字符', src: '《编辑项范围限制》' },
  floatEpsilon: { value: 0.0001, unit: '', src: '《编辑项范围限制》', note: '浮点自定义变量精度' },
  timerMinInterval: {
    value: 0.03, unit: '秒',
    src: '《定时器》',
    note: '定时器序列的最小间隔 ≈ 33 次/秒。**这是节点图唯一能做到的"周期性"** —— 没有每帧执行节点。'
  }
};

// 槽位数能不能塞进一条路径
export function checkWaypointFit(slotCount) {
  const max = LIMITS.pathWaypoints.value;
  return { ok: slotCount <= max, slotCount: slotCount, max: max, over: Math.max(0, slotCount - max) };
}

// 给 CLI 用的一行结论
export function waypointFitLine(id, slotCount) {
  const r = checkWaypointFit(slotCount);
  if (r.ok) return '  ' + id.padEnd(14) + '槽位 ' + String(slotCount).padStart(3) + '  ✓ 塞得进一条路径';
  return '  ' + id.padEnd(14) + '槽位 ' + String(slotCount).padStart(3) +
    '  ★ 超出 ' + r.over + ' 个（上限 ' + r.max + '）—— 必须把轨道做短或把球数调少';
}
