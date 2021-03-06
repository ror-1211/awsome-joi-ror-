# frozen_string_literal: true

module Joi
  class Runner
    attr_reader :root_dir, :watchers, :preset, :options

    def initialize(
      options:,
      root_dir: Dir.pwd,
      preset: Presets::Default.new(self, options)
    )
      @options = options
      @root_dir = Pathname.new(root_dir)
      @watchers = []
      @preset = preset
    end

    def run_all
      watchers.each {|watcher| watcher[:thread]&.kill }
      preset.run_all
    end

    def start
      preset.register
      run_all

      listener = Listen.to(
        root_dir.to_s,
        ignore: [%r{(public|node_modules|assets|vendor)/}],
        only: [/\.(rb)$/]
      ) do |modified, added, removed|
        modified = convert_to_relative_paths(modified)
        added = convert_to_relative_paths(added)
        removed = convert_to_relative_paths(removed)

        if options[:debug]
          debug("added files:", added.map(&:to_s).inspect)
          debug("modified files:", modified.map(&:to_s).inspect)
          debug("removed files:", removed.map(&:to_s).inspect)
        end

        watchers.each do |watcher|
          run_watcher(
            watcher,
            modified: modified,
            added: added,
            removed: removed
          )
        end
      end

      listener.start

      sleep
    end

    def debug(*args)
      return unless options[:debug]

      puts ["\e[37m[debug]\e[0m", *args].join(" ")
    end

    def log_command(command)
      puts ["\e[37m$ ", command, "\e[0m"].join
    end

    def run_watcher(watcher, modified:, added:, removed:)
      paths = []
      paths += modified if watcher[:on].include?(:modified)
      paths += added if watcher[:on].include?(:added)
      paths += removed if watcher[:on].include?(:removed)
      paths = paths.select do |path|
        watcher[:pattern].any? {|pattern| path.to_s.match?(pattern) }
      end

      unless paths.any?
        debug("skipping watcher:", watcher.slice(:on, :pattern))
        return
      end

      debug("running watcher:", watcher.slice(:on, :pattern))

      watcher[:thread]&.kill
      watcher[:thread] = Thread.new { watcher[:command].call(paths) }
    end

    def watch(watcher)
      watchers << watcher
    end

    def convert_to_relative_paths(paths)
      paths.map {|file| Pathname.new(file).relative_path_from(root_dir) }
    end
  end
end
