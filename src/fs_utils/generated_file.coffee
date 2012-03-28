common = require './common'
helpers = require '../helpers'
logger = require '../logger'

# The definition would be added on top of every filewriter .js file.
requireDefinition = '''
(function(/*! Brunch !*/) {
  'use strict';

  if (!this.require) {
    var modules = {};
    var cache = {};
    var __hasProp = ({}).hasOwnProperty;

    var getModule = function(path) {
      var dirIndex;
      if (__hasProp.call(modules, path)) return modules[path];
      dirIndex = expand(path, './index');
      if (__hasProp.call(modules, dirIndex)) return modules[dirIndex];
    };

    var expand = function(root, name) {
      var results = [], parts, part;
      if (/^\\.\\.?(\\/|$)/.test(name)) {
        parts = [root, name].join('/').split('/');
      } else {
        parts = name.split('/');
      }
      for (var i = 0, length = parts.length; i < length; i++) {
        part = parts[i];
        if (part == '..') {
          results.pop();
        } else if (part != '.' && part != '') {
          results.push(part);
        }
      }
      return results.join('/');
    };

    var require = function(name, root) {
      var path = expand(root, name);
      var dirIndex = expand(path, './index');
      var module, loader;

      if (__hasProp.call(cache, name)) {
        return cache[name];
      } else if (loader = getModule(path)) {
        module = {id: name, exports: {}};
        try {
          cache[name] = module.exports;
          loader(module.exports, function(name) {
            return require(name, dirname(path));
          }, module);
          cache[name] = module.exports;
          return cache[name];
        } catch (err) {
          delete cache[name];
          throw err;
        }
      } else {
        throw new Error("Cannot find module '" + name + "'");
      }
    };

    var dirname = function(path) {
      return path.split('/').slice(0, -1).join('/');
    };

    this.require = function(name) {
      return require(name, '');
    };

    this.require.brunch = true;
    this.require.define = function(bundle) {
      for (var key in bundle) {
        if (__hasProp.call(bundle, key)) {
          modules[key] = bundle[key];
        }
      }
    };
  }
}).call(this);
'''

sortAlphabetically = (a, b) ->
  if a < b
    -1
  else if a > b
    1
  else
    0

sortByVendor = (config, a, b) ->
  # If item path starts with 'vendor', it has bigger priority.
  # TODO: check for config.vendorPath
  vendorPath = 'vendor'
  aIsVendor = helpers.startsWith a, vendorPath
  bIsVendor = helpers.startsWith a, vendorPath
  if aIsVendor and not bIsVendor
    -1
  else if not aIsVendor and bIsVendor
    1
  else
    # All conditions were false, we don't care about order of
    # these two items.
    sortAlphabetically a, b

sortByAfter = (config, a, b) ->
  # Items wasn't found in config.before, try to find then in
  # config.after.
  # Item that config.after contains would have lower sorting index.
  indexOfA = config.after.indexOf a
  indexOfB = config.after.indexOf b
  [hasA, hasB] = [(indexOfA isnt -1), (indexOfB isnt -1)]
  if hasA and not hasB
    1
  else if not hasA and hasB
    -1
  else if hasA and hasB
    indexOfA - indexOfB
  else
    sortByVendor config, a, b

sortByBefore = (config, a, b) ->
  # Try to find items in config.before.
  # Item that config.after contains would have bigger sorting index.
  indexOfA = config.before.indexOf a
  indexOfB = config.before.indexOf b
  [hasA, hasB] = [(indexOfA isnt -1), (indexOfB isnt -1)]
  if hasA and not hasB
    -1
  else if not hasA and hasB
    1
  else if hasA and hasB
    indexOfA - indexOfB
  else
    sortByAfter config, a, b

# Sorts by pattern.
# 
# Examples
#
#   sort ['b.coffee', 'c.coffee', 'a.coffee'],
#     before: ['a.coffee'], after: ['b.coffee']
#   # => ['a.coffee', 'c.coffee', 'b.coffee']
# 
# Returns new sorted array.
sortByConfig = (files, config) ->
  return files if typeof config isnt 'object'
  config.before ?= []
  config.after ?= []
  # Clone data to a new array.
  [files...].sort (a, b) -> sortByBefore config, a, b

# File which is generated by brunch from other files.
class exports.GeneratedFile
  # * path        - path to file that will be generated.
  # * sourceFiles - array of `fs_utils.SourceFile`-s.
  # * config      - parsed application config.
  constructor: (@path, @sourceFiles, @config) ->    
    @type = if (@sourceFiles.some (file) -> file.type is 'javascript')
      'javascript'
    else
      'stylesheet'

  _extractOrder: (files, config) ->
    types = files.map (file) -> helpers.pluralize file.type
    Object.keys(config.files)
      .filter (key) ->
        key in types
      # Extract order value from config.
      .map (key) ->
        config.files[key].order
      # Join orders together.
      .reduce (memo, array) ->
        array or= {}
        {
          before: memo.before.concat(array.before or []),
          after: memo.after.concat(array.after or [])
        }
      , {before: [], after: []}

  # Collects content from a list of files and wraps it with
  # require.js module definition if needed.
  joinSourceFiles: ->
    files = @sourceFiles
    pathes = files.map (file) -> file.path
    order = @_extractOrder files, @config
    sourceFiles = (sortByConfig pathes, order).map (file) ->
      files[pathes.indexOf file]
    data = ''
    data += requireDefinition if @type is 'javascript'
    data += sourceFiles.map((file) -> file.data).join ''
    data

  minify: (data, callback) ->
    if @config.minify and @minifier?.minify?
      @minifier.minify data, @path, callback
    else
      callback null, data

  # Joins data from source files, minifies it and writes result to 
  # path of current generated file.
  write: (callback) ->
    files = (@sourceFiles.map (file) -> file.path).join(', ')
    logger.log 'debug', "Writing files '#{files}' to '#{@path}'"
    @minify @joinSourceFiles(), (error, data) =>
      common.writeFile @path, data, callback
