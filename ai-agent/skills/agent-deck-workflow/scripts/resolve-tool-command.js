#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_CONFIG_PATH = path.resolve(
  __dirname,
  "../../../config/tool-profiles.toml"
);
const DEFAULT_LOCAL_CONFIG_PATH = path.resolve(
  __dirname,
  "../../../config/tool-profiles.local.toml"
);

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

function mergeToolConfigs(baseConfig, overrideConfig) {
  if (!overrideConfig) {
    return {
      version: baseConfig.version,
      roles: { ...baseConfig.roles },
      profiles: Object.fromEntries(
        Object.entries(baseConfig.profiles).map(([name, profile]) => [name, { ...profile }])
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
      Object.entries(baseConfig.profiles).map(([name, profile]) => [name, { ...profile }])
    ),
  };

  for (const [name, profile] of Object.entries(overrideConfig.profiles || {})) {
    merged.profiles[name] = {
      ...(merged.profiles[name] || {}),
      ...profile,
    };
  }

  return merged;
}

function loadToolConfig(configPath = DEFAULT_CONFIG_PATH, localConfigPath = DEFAULT_LOCAL_CONFIG_PATH) {
  if (!fs.existsSync(configPath)) {
    throw new Error(`tool profile config not found: ${configPath}`);
  }
  const baseConfig = parseToolProfilesToml(fs.readFileSync(configPath, "utf8"));
  if (!fs.existsSync(localConfigPath)) {
    return mergeToolConfigs(baseConfig, null);
  }
  const localConfig = parseToolProfilesToml(fs.readFileSync(localConfigPath, "utf8"));
  return mergeToolConfigs(baseConfig, localConfig);
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

function resolveProfileCommand(config, profileName, resolutionSource, excludedCommands = []) {
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
  const selectedIndex = candidates.findIndex(
    (candidate) => !excludedCommands.includes(candidate)
  );
  if (selectedIndex === -1) {
    throw new Error(`no remaining candidates for tool profile: ${profileName}`);
  }
  return {
    tool_profile: profileName,
    resolved_tool_cmd: candidates[selectedIndex],
    resolution_source: resolutionSource,
    fallback_index: selectedIndex,
    candidate_count: candidates.length,
  };
}

function resolveToolCommand(options = {}) {
  const {
    role = "",
    profile = "",
    command = "",
    inheritCommand = "",
    excludedCommands = [],
    config = loadToolConfig(),
  } = options;

  if (command) {
    return {
      tool_profile: profile || "explicit",
      resolved_tool_cmd: command,
      resolution_source: "explicit_command",
      fallback_index: 0,
      candidate_count: 1,
    };
  }

  const resolvedProfile = resolveProfileName(config, "", profile);
  if (resolvedProfile) {
    return resolveProfileCommand(
      config,
      resolvedProfile,
      "explicit_profile",
      excludedCommands
    );
  }

  if (inheritCommand) {
    return {
      tool_profile: "inherited",
      resolved_tool_cmd: inheritCommand,
      resolution_source: "inherit_command",
      fallback_index: 0,
      candidate_count: 1,
    };
  }

  const roleDefaultProfile = resolveProfileName(config, role, "");
  if (roleDefaultProfile) {
    return resolveProfileCommand(
      config,
      roleDefaultProfile,
      "role_default_profile",
      excludedCommands
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
    configPath: DEFAULT_CONFIG_PATH,
    localConfigPath: DEFAULT_LOCAL_CONFIG_PATH,
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
    } else if (arg === "--config") {
      options.configPath = argv[++i] || "";
    } else if (arg === "--local-config") {
      options.localConfigPath = argv[++i] || "";
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
  const config = loadToolConfig(options.configPath, options.localConfigPath);
  const resolved = resolveToolCommand({
    role: options.role,
    profile: options.profile,
    command: options.command,
    inheritCommand: options.inheritCommand,
    excludedCommands: options.excludedCommands,
    config,
  });

  if (options.format === "text") {
    process.stdout.write(`${resolved.resolved_tool_cmd}\n`);
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
  loadToolConfig,
  mergeToolConfigs,
  parseToolProfilesToml,
  parseTomlValue,
  resolveToolCommand,
  resolveProfileCommand,
  runCli,
};
