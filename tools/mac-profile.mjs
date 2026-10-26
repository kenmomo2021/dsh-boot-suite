#!/usr/bin/env node
/**
 * macOS 本地安装用的 profile 助手（只给这个 fork 用，不参与上游发布包）。
 *
 * 只做三件事：
 *   1) 改 profile 的 package.json —— dependencies 里的 link: 依赖
 *   2) 改 dsh.profile.bundles —— DSH 靠它决定加载哪些插件
 *   3) 维护 profile/node_modules/dsh-boot-suite 的符号链接
 *
 * 不碰 DSH 本体，也不碰 ~/.dsh 下的用户配置（dsh-startup.json / chat-wallpaper.json /
 * startup-templates / chat-wallpaper 资源）。
 *
 * 用法：
 *   node tools/mac-profile.mjs status <profileDir>
 *   node tools/mac-profile.mjs add    <profileDir> <repoRoot>
 *   node tools/mac-profile.mjs remove <profileDir>
 */
import fs from 'node:fs'
import path from 'node:path'

const NAME = 'dsh-boot-suite'
const OLD_PLUGINS = ['dsh-startup-screen', 'dsh-chat-wallpaper']

const [cmd, profileArg, repoArg] = process.argv.slice(2)
if (!cmd || !profileArg) {
  console.error('用法: mac-profile.mjs <status|add|remove> <profileDir> [repoRoot]')
  process.exit(2)
}

const PROFILE = path.resolve(profileArg)
const PKG_FILE = path.join(PROFILE, 'package.json')
const NODE_MODULES = path.join(PROFILE, 'node_modules')
const LINK = path.join(NODE_MODULES, NAME)

function die(msg) {
  console.error('[x] ' + msg)
  process.exit(1)
}

function readPkg() {
  return JSON.parse(fs.readFileSync(PKG_FILE, 'utf8').replace(/^\uFEFF/, ''))
}

function writePkg(pkg) {
  fs.writeFileSync(PKG_FILE, JSON.stringify(pkg, null, 2) + '\n', 'utf8')
}

function bundlesOf(pkg) {
  return Array.isArray(pkg?.dsh?.profile?.bundles) ? pkg.dsh.profile.bundles.slice() : []
}

function linkTarget() {
  try { return fs.readlinkSync(LINK) } catch { return '' }
}

function linkValid() {
  try { return fs.statSync(LINK).isDirectory() && fs.existsSync(path.join(LINK, 'package.json')) } catch { return false }
}

function removeLink() {
  try {
    const st = fs.lstatSync(LINK)
    if (st.isSymbolicLink() || st.isFile()) fs.unlinkSync(LINK)
    else if (st.isDirectory()) fs.rmSync(LINK, { recursive: true, force: true })
  } catch { /* 不存在就算了 */ }
}

function cleanBundles(list) {
  const out = list.filter((x) => x !== NAME && !OLD_PLUGINS.includes(x))
  /* 跟作者 install.ps1 一致：插在 dsh-plugin-desktop-notify 之前，没有就放末尾 */
  const idx = out.indexOf('dsh-plugin-desktop-notify')
  if (idx > 0) out.splice(idx, 0, NAME)
  else out.push(NAME)
  return out
}

function setBundles(pkg, list) {
  if (!pkg.dsh || typeof pkg.dsh !== 'object') pkg.dsh = {}
  if (!pkg.dsh.profile || typeof pkg.dsh.profile !== 'object') pkg.dsh.profile = {}
  pkg.dsh.profile.bundles = list
}

function add(repoRoot) {
  if (!repoRoot) die('缺少 repoRoot 参数')
  const repo = path.resolve(repoRoot)
  const repoPkgFile = path.join(repo, 'package.json')
  if (!fs.existsSync(repoPkgFile)) die('不是插件目录：' + repo)
  const repoPkg = JSON.parse(fs.readFileSync(repoPkgFile, 'utf8').replace(/^\uFEFF/, ''))
  if (repoPkg.name !== NAME) die('仓库 package.json 的 name 不是 ' + NAME + '：' + repoPkg.name)
  if (!fs.existsSync(path.join(repo, 'lib', 'index.js'))) die('源码不完整（缺 lib/index.js）')

  if (!fs.existsSync(PKG_FILE)) die('profile 没有 package.json：' + PKG_FILE)
  const pkg = readPkg()

  if (!pkg.dependencies || typeof pkg.dependencies !== 'object') pkg.dependencies = {}
  for (const old of OLD_PLUGINS) delete pkg.dependencies[old]
  pkg.dependencies[NAME] = 'link:' + repo.split(path.sep).join('/')

  setBundles(pkg, cleanBundles(bundlesOf(pkg)))
  writePkg(pkg)

  fs.mkdirSync(NODE_MODULES, { recursive: true })
  removeLink()
  fs.symlinkSync(repo, LINK, 'dir')

  console.log('  package.json  dependencies["' + NAME + '"] = link:' + repo)
  console.log('  package.json  bundles 已登记 ' + NAME)
  console.log('  node_modules/' + NAME + ' -> ' + repo)
}

function remove() {
  if (!fs.existsSync(PKG_FILE)) die('profile 没有 package.json：' + PKG_FILE)
  const pkg = readPkg()
  if (pkg.dependencies && typeof pkg.dependencies === 'object') {
    delete pkg.dependencies[NAME]
    for (const old of OLD_PLUGINS) delete pkg.dependencies[old]
  }
  if (Array.isArray(pkg?.dsh?.profile?.bundles)) {
    pkg.dsh.profile.bundles = pkg.dsh.profile.bundles.filter((x) => x !== NAME && !OLD_PLUGINS.includes(x))
  }
  writePkg(pkg)
  removeLink()
  console.log('  已从 dependencies / bundles / node_modules 移除 ' + NAME)
}

function status() {
  const out = {
    profile: PROFILE,
    packageJson: fs.existsSync(PKG_FILE),
    dependency: '',
    inBundles: false,
    linkTarget: linkTarget(),
    linkValid: linkValid(),
    installedVersion: '',
    repoVersion: ''
  }
  if (out.packageJson) {
    const pkg = readPkg()
    out.dependency = pkg?.dependencies?.[NAME] || ''
    out.inBundles = bundlesOf(pkg).includes(NAME)
  }
  if (out.linkValid) {
    try { out.installedVersion = JSON.parse(fs.readFileSync(path.join(LINK, 'package.json'), 'utf8')).version } catch { /* 忽略 */ }
  }
  console.log(JSON.stringify(out, null, 2))
  process.exit(out.dependency && out.inBundles && out.linkValid ? 0 : 1)
}

switch (cmd) {
  case 'status': status(); break
  case 'add': add(repoArg); break
  case 'remove': remove(); break
  default: die('未知命令：' + cmd)
}
