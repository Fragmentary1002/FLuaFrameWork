const fs = require("node:fs");
const path = require("node:path");

const frameworkRoot = path.join(process.cwd(), "FLuaFramework");
const registerPath = path.join(frameworkRoot, "register.lua");
const violations = [];

function visit(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      visit(entryPath);
    } else if (entryPath.endsWith(".lua") && entryPath !== registerPath) {
      const source = fs.readFileSync(entryPath, "utf8");
      if (/\brequire\s*\(/.test(source)) {
        violations.push(path.relative(process.cwd(), entryPath));
      }
    }
  }
}

visit(frameworkRoot);

if (violations.length > 0) {
  console.error("Only FLuaFramework/register.lua may require framework dependencies:");
  for (const violation of violations) {
    console.error(`- ${violation}`);
  }
  process.exit(1);
}

console.log("framework require check passed");
