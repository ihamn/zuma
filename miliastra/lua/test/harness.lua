-- 极简测试框架（本地用）。用法：
--   local H = require('harness')
--   H.suite('xxx')
--   H.ok(cond, '说明')
--   H.eq(a, b, '说明')
--   H.finish()          -- 打印结果并以退出码返回
--
-- 为什么不塞进 lua/src：那里是**要被上传到千星奇域**的真源，
-- 不许出现 os.exit / io 这类东西（tools/check-lua-sandbox.mjs 会拦）。

local H = { pass = 0, fail = 0, name = 'test', msgs = {} }

function H.suite(name) H.name = name end

local function record(ok, msg)
  if ok then
    H.pass = H.pass + 1
  else
    H.fail = H.fail + 1
    H.msgs[#H.msgs + 1] = msg or '(无说明)'
  end
  return ok
end

function H.ok(cond, msg) return record(cond and true or false, msg) end

function H.eq(a, b, msg)
  local ok = (a == b)
  if not ok then msg = (msg or '') .. '  期望=' .. tostring(b) .. ' 实际=' .. tostring(a) end
  return record(ok, msg)
end

function H.near(a, b, tol, msg)
  tol = tol or 1e-6
  local ok = type(a) == 'number' and type(b) == 'number' and math.abs(a - b) <= tol
  if not ok then msg = (msg or '') .. '  期望≈' .. tostring(b) .. ' 实际=' .. tostring(a) end
  return record(ok, msg)
end

function H.truthy(a, msg) return record(a ~= nil and a ~= false, msg) end

function H.finish()
  for i = 1, #H.msgs do print('  ✗ ' .. H.msgs[i]) end
  print(string.format('%s: %d 通过 / %d 失败', H.name, H.pass, H.fail))
  os.exit(H.fail == 0 and 0 or 1)
end

return H
