#!/usr/bin/env node

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

function resolveAiAgentConfigDir(env = process.env, homeDir = os.homedir()) {
  const xdgConfigHome = env.XDG_CONFIG_HOME || path.join(homeDir, ".config");
  return path.resolve(xdgConfigHome, "ai-agent", "config");
}

function uniquePaths(paths) {
  return [...new Set(paths.filter(Boolean).map((configPath) => path.resolve(configPath)))];
}

function resolveCwdLocalConfigPath(cwd = process.cwd()) {
  return path.resolve(cwd, "tool-profiles.local.toml");
}

function resolveDefaultLocalConfigPaths(
  env = process.env,
  homeDir = os.homedir(),
  cwd = process.cwd()
) {
  return uniquePaths([
    path.join(resolveAiAgentConfigDir(env, homeDir), "tool-profiles.local.toml"),
    resolveCwdLocalConfigPath(cwd),
  ]);
}

const DEFAULT_CONFIG_PATH = path.join(
  resolveAiAgentConfigDir(),
  "tool-profiles.toml"
);
const DEFAULT_LOCAL_CONFIG_PATH = path.join(
  resolveAiAgentConfigDir(),
  "tool-profiles.local.toml"
);
const DEFAULT_LOCAL_CONFIG_PATHS = resolveDefaultLocalConfigPaths();

function stripInlineComment(line) {
  let escaped = false;
  let stringQuote = "";
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (escaped && stringQuote === "\"") {
      escaped = false;
      continue;
    }
    if (ch === "\\" && stringQuote === "\"") {
      escaped = true;
      continue;
    }
    if ((ch === "\"" || ch === "'") && !stringQuote) {
      stringQuote = ch;
      continue;
    }
    if (ch === stringQuote) {
      stringQuote = "";
      continue;
    }
    if (ch === "#" && !stringQuote) {
      return line.slice(0, i);
    }
  }
  return line;
}

function countCharOutsideStrings(text, target) {
  let escaped = false;
  let stringQuote = "";
  let count = 0;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (escaped && stringQuote === "\"") {
      escaped = false;
      continue;
    }
    if (ch === "\\" && stringQuote === "\"") {
      escaped = true;
      continue;
    }
    if ((ch === "\"" || ch === "'") && !stringQuote) {
      stringQuote = ch;
      continue;
    }
    if (ch === stringQuote) {
      stringQuote = "";
      continue;
    }
    if (!stringQuote && ch === target) {
      count += 1;
    }
  }
  return count;
}

function parseSingleQuotedString(value) {
  if (!value.startsWith("'") || !value.endsWith("'")) {
    throw new Error(`invalid TOML literal string: ${value}`);
  }
  const inner = value.slice(1, -1);
  return inner.replace(/''/g, "'");
}

function splitTomlArrayItems(value) {
  const inner = value.slice(1, -1).trim();
  if (!inner) {
    return [];
  }

  const items = [];
  let current = "";
  let escaped = false;
  let stringQuote = "";
  let nestedDepth = 0;

  for (let i = 0; i < inner.length; i += 1) {
    const ch = inner[i];

    if (stringQuote === "\"") {
      current += ch;
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch === "\\") {
        escaped = true;
        continue;
      }
      if (ch === "\"") {
        stringQuote = "";
      }
      continue;
    }

    if (stringQuote === "'") {
      current += ch;
      if (ch === "'") {
        if (inner[i + 1] === "'") {
          current += "'";
          i += 1;
        } else {
          stringQuote = "";
        }
      }
      continue;
    }

    if (ch === "\"" || ch === "'") {
      stringQuote = ch;
      current += ch;
      continue;
    }

    if (ch === "[") {
      nestedDepth += 1;
      current += ch;
      continue;
    }
    if (ch === "]") {
      nestedDepth -= 1;
      current += ch;
      continue;
    }
    if (ch === "," && nestedDepth === 0) {
      const item = current.trim();
      if (item) {
        items.push(item);
      }
      current = "";
      continue;
    }

    current += ch;
  }

  const tail = current.trim();
  if (tail) {
    items.push(tail);
  }

  return items;
}

function parseTomlValue(rawValue) {
  const value = rawValue.trim();
  if (!value.length) {
    throw new Error("empty TOML value");
  }
  if (value.startsWith("\"")) {
    return JSON.parse(value);
  }
  if (value.startsWith("'")) {
    return parseSingleQuotedString(value);
  }
  if (value.startsWith("[")) {
    return splitTomlArrayItems(value).map((item) => parseTomlValue(item));
  }
  if (/^(true|false)$/.test(value)) {
    return value === "true";
  }
  if (/^-?\d+$/.test(value)) {
    return Number.parseInt(value, 10);
  }
  throw new Error(`unsupported TOML value: ${value}`);
}

function ensureSectionTarget(config, sectionName) {
  if (sectionName === "roles") {
    config.roles ||= {};
    return config.roles;
  }
  if (sectionName.startsWith("profiles.")) {
    const profileName = sectionName.slice("profiles.".length).trim();
    if (!profileName) {
      throw new Error("profile section name is empty");
    }
    config.profiles ||= {};
    config.profiles[profileName] ||= {};
    return config.profiles[profileName];
  }
  throw new Error(`unsupported TOML section: ${sectionName}`);
}

function parseToolProfilesToml(text) {
  const config = {
    version: null,
    roles: {},
    profiles: {},
  };
  const lines = text.split(/\r?\n/);
  let currentTarget = config;
  let currentSection = "";

  for (let i = 0; i < lines.length; i += 1) {
    let line = stripInlineComment(lines[i]).trim();
    if (!line) {
      continue;
    }

    const sectionMatch = line.match(/^\[(.+)]$/);
    if (sectionMatch) {
      currentSection = sectionMatch[1].trim();
      currentTarget = ensureSectionTarget(config, currentSection);
      continue;
    }

    const eqIndex = line.indexOf("=");
    if (eqIndex === -1) {
      throw new Error(`invalid TOML assignment on line ${i + 1}`);
    }

    const key = line.slice(0, eqIndex).trim();
    let rawValue = line.slice(eqIndex + 1).trim();

    if (countCharOutsideStrings(rawValue, "[") > countCharOutsideStrings(rawValue, "]")) {
      while (i + 1 < lines.length) {
        i += 1;
        rawValue += `\n${stripInlineComment(lines[i]).trim()}`;
        if (
          countCharOutsideStrings(rawValue, "[") ===
          countCharOutsideStrings(rawValue, "]")
        ) {
          break;
        }
      }
    }

    currentTarget[key] = parseTomlValue(rawValue);
  }

  return config;
}

const CANDIDATE_MERGE_MODES = new Set(["replace", "prepend", "append"]);

function mergeProfile(baseProfile = {}, overrideProfile = {}) {
  const baseCandidates = baseProfile.candidates;
  const baseFields = { ...baseProfile };
  delete baseFields.merge;
  delete baseFields.candidates;
  const {
    merge: candidateMerge,
    candidates: overrideCandidates,
    ...overrideFields
  } = overrideProfile;
  const merged = { ...baseFields, ...overrideFields };

  if (candidateMerge !== undefined && !CANDIDATE_MERGE_MODES.has(candidateMerge)) {
    throw new Error(`unsupported candidate merge mode: ${candidateMerge}`);
  }
  if (candidateMerge !== undefined && overrideCandidates === undefined) {
    throw new Error("candidate merge mode requires candidates");
  }
  if (overrideCandidates === undefined) {
    if (baseCandidates !== undefined) {
      if (!Array.isArray(baseCandidates)) {
        throw new Error("profile candidates must be an array");
      }
      merged.candidates = [...baseCandidates];
    }
    return merged;
  }
  if (!Array.isArray(overrideCandidates)) {
    throw new Error("profile candidates must be an array");
  }

  const priorCandidates = Array.isArray(baseCandidates) ? baseCandidates : [];
  const mergeMode = candidateMerge || "replace";
  if (mergeMode === "prepend") {
    merged.candidates = [...overrideCandidates, ...priorCandidates];
  } else if (mergeMode === "append") {
    merged.candidates = [...priorCandidates, ...overrideCandidates];
  } else {
    merged.candidates = [...overrideCandidates];
  }
  return merged;
}

function mergeToolConfigs(baseConfig, overrideConfig) {
  if (!overrideConfig) {
    return {
      version: baseConfig.version,
      roles: { ...baseConfig.roles },
      profiles: Object.fromEntries(
        Object.entries(baseConfig.profiles).map(([name, profile]) => [
          name,
          mergeProfile({}, profile),
        ])
      ),
    };
  }

  const merged = {
    version: overrideConfig.version ?? baseConfig.version,
    roles: {
      ...baseConfig.roles,
      ...overrideConfig.roles,
    },
    profiles: Object.fromEntries(
      Object.entries(baseConfig.profiles).map(([name, profile]) => [
        name,
        mergeProfile({}, profile),
      ])
    ),
  };

  for (const [name, profile] of Object.entries(overrideConfig.profiles || {})) {
    merged.profiles[name] = mergeProfile(merged.profiles[name], profile);
  }

  return merged;
}

function loadToolConfig(
  configPath = DEFAULT_CONFIG_PATH,
  localConfigPaths = resolveDefaultLocalConfigPaths()
) {
  if (!fs.existsSync(configPath)) {
    throw new Error(`tool profile config not found: ${configPath}`);
  }
  const baseConfig = parseToolProfilesToml(fs.readFileSync(configPath, "utf8"));
  let mergedConfig = mergeToolConfigs(baseConfig, null);

  for (const localConfigPath of uniquePaths(
    Array.isArray(localConfigPaths) ? localConfigPaths : [localConfigPaths]
  )) {
    if (!fs.existsSync(localConfigPath)) {
      continue;
    }
    const localConfig = parseToolProfilesToml(fs.readFileSync(localConfigPath, "utf8"));
    mergedConfig = mergeToolConfigs(mergedConfig, localConfig);
  }

  return mergedConfig;
}

function splitCommandLine(commandLine) {
  const words = [];
  let current = "";
  let quote = "";
  let escaped = false;
  let hasWord = false;

  for (let i = 0; i < commandLine.length; i += 1) {
    const ch = commandLine[i];
    if (escaped) {
      current += ch;
      hasWord = true;
      escaped = false;
      continue;
    }
    if (quote === "'") {
      if (ch === "'") {
        quote = "";
      } else {
        current += ch;
      }
      hasWord = true;
      continue;
    }
    if (quote === '"') {
      if (ch === '"') {
        quote = "";
      } else if (ch === "\\") {
        escaped = true;
      } else {
        current += ch;
      }
      hasWord = true;
      continue;
    }
    if (ch === "\\") {
      escaped = true;
      hasWord = true;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      hasWord = true;
      continue;
    }
    if (/\s/.test(ch)) {
      if (hasWord) {
        words.push(current);
        current = "";
        hasWord = false;
      }
      continue;
    }
    current += ch;
    hasWord = true;
  }

  if (quote || escaped) {
    return null;
  }
  if (hasWord) {
    words.push(current);
  }
  return words;
}

function parseEnvironmentAssignment(word) {
  const match = word.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/s);
  return match ? { name: match[1], value: match[2] } : null;
}

function skipCommandOptions(words, startIndex, environment) {
  let index = startIndex;
  while (index < words.length) {
    const word = words[index];
    if (word === "--") {
      return index + 1;
    }
    const assignment = parseEnvironmentAssignment(word);
    if (assignment) {
      environment[assignment.name] = assignment.value;
      index += 1;
      continue;
    }
    if (word === "-u" || word === "--unset") {
      index += 2;
      continue;
    }
    if (word.startsWith("-")) {
      index += 1;
      continue;
    }
    return index;
  }
  return index;
}

function extractCommandExecutable(commandLine) {
  const words = splitCommandLine(commandLine);
  if (!words || !words.length) {
    return { reason: "command_not_parseable" };
  }

  const environment = {};
  let index = 0;
  while (index < words.length) {
    const assignment = parseEnvironmentAssignment(words[index]);
    if (!assignment) {
      break;
    }
    environment[assignment.name] = assignment.value;
    index += 1;
  }
  while (words[index] === "env" || words[index] === "command" || words[index] === "exec") {
    index = skipCommandOptions(words, index + 1, environment);
  }

  const executable = words[index];
  if (!executable) {
    return { reason: "executable_not_detectable" };
  }
  if (/[$`*?\[\]{}]/.test(executable) || executable.startsWith("~")) {
    return { reason: "executable_not_static" };
  }
  return {
    executable,
    path_env: Object.prototype.hasOwnProperty.call(environment, "PATH")
      ? environment.PATH
      : undefined,
  };
}

function inspectToolCommand(
  toolCmd,
  {
    pathEnv = process.env.PATH,
    cwd = process.cwd(),
    pathTrusted = false,
    cwdTrusted = false,
  } = {}
) {
  const extracted = extractCommandExecutable(toolCmd);
  if (!extracted.executable) {
    return {
      availability: "unverified",
      tool_cmd: toolCmd,
      reason: extracted.reason,
    };
  }

  const executable = extracted.executable;
  const executableIsPath = executable.includes("/");
  if (executableIsPath && !path.isAbsolute(executable) && !cwdTrusted) {
    return {
      availability: "unverified",
      tool_cmd: toolCmd,
      executable,
      reason: "target_workdir_unknown",
    };
  }

  const commandPathIsStatic =
    extracted.path_env !== undefined &&
    !/[$`*?\[\]{}~]/.test(extracted.path_env);
  if (extracted.path_env !== undefined && !commandPathIsStatic) {
    return {
      availability: "unverified",
      tool_cmd: toolCmd,
      executable,
      reason: "command_path_not_static",
    };
  }
  const effectivePath = commandPathIsStatic ? extracted.path_env : pathEnv;
  const candidatePaths = executableIsPath
    ? [path.resolve(cwd, executable)]
    : String(effectivePath || "")
        .split(path.delimiter)
        .map((directory) => path.resolve(directory || cwd, executable));
  let foundNonExecutable = false;

  for (const candidatePath of candidatePaths) {
    try {
      if (!fs.statSync(candidatePath).isFile()) {
        foundNonExecutable = true;
        continue;
      }
      fs.accessSync(candidatePath, fs.constants.X_OK);
      return {
        availability: "available",
        tool_cmd: toolCmd,
        executable,
      };
    } catch {
      if (fs.existsSync(candidatePath)) {
        foundNonExecutable = true;
      }
    }
  }

  const contextIsTrusted = executableIsPath
    ? cwdTrusted
    : pathTrusted && extracted.path_env === undefined;
  const reason = foundNonExecutable
    ? "not_executable"
    : executableIsPath
      ? "not_found_at_path"
      : extracted.path_env !== undefined
        ? "not_found_on_command_path"
        : pathTrusted
          ? "not_found_on_target_path"
          : "not_found_on_dispatcher_path";
  return {
    availability: contextIsTrusted ? "unavailable" : "unverified",
    tool_cmd: toolCmd,
    executable,
    reason,
  };
}

function toolCommandDiagnostic(inspection, candidateIndex) {
  const diagnostic = {
    tool_cmd: inspection.tool_cmd,
    reason: inspection.reason,
    candidate_index: candidateIndex,
  };
  if (inspection.executable) {
    diagnostic.executable = inspection.executable;
  }
  return diagnostic;
}

function noUsableToolCommandsError(profileName, unavailableToolCmds) {
  const details = unavailableToolCmds
    .map(({ tool_cmd, executable, reason }) =>
      executable ? `${executable}: ${reason} (${tool_cmd})` : `${reason} (${tool_cmd})`
    )
    .join("; ");
  const error = new Error(`no usable tool commands for profile ${profileName}: ${details}`);
  error.unavailable_tool_cmds = unavailableToolCmds;
  return error;
}

function resolveProfileName(config, role, explicitProfile) {
  if (explicitProfile) {
    return explicitProfile;
  }
  if (role && config.roles[role]) {
    return config.roles[role];
  }
  return "";
}

function resolveProfileCommand(
  config,
  profileName,
  resolutionSource,
  excludedCommands = [],
  showList = false,
  inspectCommand = inspectToolCommand,
  inspectionOptions = {}
) {
  const profileConfig = config.profiles[profileName];
  if (!profileConfig) {
    throw new Error(`unknown tool profile: ${profileName}`);
  }
  if (profileConfig.strategy !== "ordered") {
    throw new Error(`unsupported tool profile strategy: ${profileConfig.strategy}`);
  }
  const candidates = Array.isArray(profileConfig.candidates)
    ? profileConfig.candidates
    : [];
  const unavailableToolCmds = [];
  const unverifiedToolCmds = [];
  const usableToolCmds = [];
  for (let candidateIndex = 0; candidateIndex < candidates.length; candidateIndex += 1) {
    const toolCmd = candidates[candidateIndex];
    if (excludedCommands.includes(toolCmd)) {
      continue;
    }
    const inspection = inspectCommand(toolCmd, inspectionOptions);
    if (inspection.availability === "unavailable") {
      unavailableToolCmds.push(toolCommandDiagnostic(inspection, candidateIndex));
      continue;
    }
    if (inspection.availability === "unverified") {
      unverifiedToolCmds.push(toolCommandDiagnostic(inspection, candidateIndex));
    }
    usableToolCmds.push({ toolCmd, candidateIndex });
  }
  const toolCmds = usableToolCmds.map(({ toolCmd }) => toolCmd);
  if (!toolCmds.length) {
    if (unavailableToolCmds.length) {
      throw noUsableToolCommandsError(profileName, unavailableToolCmds);
    }
    throw new Error(`no remaining candidates for tool profile: ${profileName}`);
  }
  const selectedIndex = usableToolCmds[0].candidateIndex;
  const resolved = {
    tool_profile: profileName,
    resolved_tool_cmd: toolCmds[0],
    resolution_source: resolutionSource,
    fallback_index: selectedIndex,
    candidate_count: candidates.length,
  };
  if (unavailableToolCmds.length) {
    resolved.unavailable_tool_cmds = unavailableToolCmds;
  }
  if (unverifiedToolCmds.length) {
    resolved.unverified_tool_cmds = unverifiedToolCmds;
  }
  if (showList) {
    resolved.tool_cmds = toolCmds;
  }
  return resolved;
}

function resolveSingleToolCommand(
  toolCmd,
  toolProfile,
  resolutionSource,
  showList,
  inspectCommand,
  inspectionOptions
) {
  const inspection = inspectCommand(toolCmd, inspectionOptions);
  if (inspection.availability === "unavailable") {
    throw noUsableToolCommandsError(toolProfile, [toolCommandDiagnostic(inspection, 0)]);
  }
  const resolved = {
    tool_profile: toolProfile,
    resolved_tool_cmd: toolCmd,
    resolution_source: resolutionSource,
    fallback_index: 0,
    candidate_count: 1,
  };
  if (inspection.availability === "unverified") {
    resolved.unverified_tool_cmds = [toolCommandDiagnostic(inspection, 0)];
  }
  if (showList) {
    resolved.tool_cmds = [toolCmd];
  }
  return resolved;
}

function resolveToolCommand(options = {}) {
  const {
    role = "",
    profile = "",
    command = "",
    inheritCommand = "",
    excludedCommands = [],
    showList = false,
    inspectCommand = inspectToolCommand,
    inspectionOptions = {},
    config = loadToolConfig(),
  } = options;

  if (command) {
    return resolveSingleToolCommand(
      command,
      profile || "explicit",
      "explicit_command",
      showList,
      inspectCommand,
      inspectionOptions
    );
  }

  const resolvedProfile = resolveProfileName(config, "", profile);
  if (resolvedProfile) {
    return resolveProfileCommand(
      config,
      resolvedProfile,
      "explicit_profile",
      excludedCommands,
      showList,
      inspectCommand,
      inspectionOptions
    );
  }

  if (inheritCommand) {
    return resolveSingleToolCommand(
      inheritCommand,
      "inherited",
      "inherit_command",
      showList,
      inspectCommand,
      inspectionOptions
    );
  }

  const roleDefaultProfile = resolveProfileName(config, role, "");
  if (roleDefaultProfile) {
    return resolveProfileCommand(
      config,
      roleDefaultProfile,
      "role_default_profile",
      excludedCommands,
      showList,
      inspectCommand,
      inspectionOptions
    );
  }

  throw new Error("tool resolution requires an explicit command, profile, inherited command, or role default");
}

function parseArgs(argv) {
  const options = {
    role: "",
    profile: "",
    command: "",
    inheritCommand: "",
    excludedCommands: [],
    showList: false,
    workdir: "",
    targetPath: "",
    configPath: DEFAULT_CONFIG_PATH,
    localConfigPaths: resolveDefaultLocalConfigPaths(),
    format: "json",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--role") {
      options.role = argv[++i] || "";
    } else if (arg === "--profile") {
      options.profile = argv[++i] || "";
    } else if (arg === "--command") {
      options.command = argv[++i] || "";
    } else if (arg === "--inherit-command") {
      options.inheritCommand = argv[++i] || "";
    } else if (arg === "--exclude-command") {
      options.excludedCommands.push(argv[++i] || "");
    } else if (arg === "--show-list") {
      options.showList = true;
    } else if (arg === "--workdir") {
      options.workdir = argv[++i] || "";
    } else if (arg === "--target-path") {
      options.targetPath = argv[++i] || "";
    } else if (arg === "--config") {
      options.configPath = argv[++i] || "";
    } else if (arg === "--local-config") {
      options.localConfigPaths = [argv[++i] || ""];
    } else if (arg === "--format") {
      options.format = argv[++i] || "json";
    } else if (arg === "--json") {
      options.format = "json";
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }

  return options;
}

function runCli(argv) {
  const options = parseArgs(argv);
  const config = loadToolConfig(options.configPath, options.localConfigPaths);
  const inspectionOptions = {
    cwd: options.workdir || process.cwd(),
    cwdTrusted: Boolean(options.workdir),
  };
  if (options.targetPath) {
    inspectionOptions.pathEnv = options.targetPath;
    inspectionOptions.pathTrusted = true;
  }
  const resolved = resolveToolCommand({
    role: options.role,
    profile: options.profile,
    command: options.command,
    inheritCommand: options.inheritCommand,
    excludedCommands: options.excludedCommands,
    showList: options.showList,
    inspectionOptions,
    config,
  });

  if (options.format === "text") {
    const output = options.showList
      ? resolved.tool_cmds.join("\n")
      : resolved.resolved_tool_cmd;
    process.stdout.write(`${output}\n`);
    return;
  }
  if (options.format !== "json") {
    throw new Error(`unsupported output format: ${options.format}`);
  }
  process.stdout.write(`${JSON.stringify(resolved, null, 2)}\n`);
}

if (require.main === module) {
  try {
    runCli(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
  }
}

module.exports = {
  DEFAULT_CONFIG_PATH,
  DEFAULT_LOCAL_CONFIG_PATH,
  DEFAULT_LOCAL_CONFIG_PATHS,
  inspectToolCommand,
  loadToolConfig,
  mergeToolConfigs,
  parseToolProfilesToml,
  parseTomlValue,
  resolveAiAgentConfigDir,
  resolveCwdLocalConfigPath,
  resolveDefaultLocalConfigPaths,
  resolveToolCommand,
  resolveProfileCommand,
  runCli,
};
