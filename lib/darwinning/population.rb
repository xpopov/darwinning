module Darwinning
  class Population

    attr_reader :members, :generations_limit, :fitness_goal, :fitness_objective,
                :organism, :population_size, :population_selection, :random_members, :generation,
                :use_threads,
                :evolution_types, :history

    DEFAULT_EVOLUTION_TYPES = [
      Darwinning::EvolutionTypes::Reproduction.new(crossover_method: :alternating_swap),
      Darwinning::EvolutionTypes::Mutation.new(mutation_rate: 0.10)
    ]

    def initialize(options = {})
      puts "initialize"
      @organism = options.fetch(:organism)
      @organism_options = options.fetch(:organism_options, {})
      @population_size = options.fetch(:population_size)
      @population_selection = options.fetch(:population_selection, (0.2 * @population_size).ceil)
      @random_members = options.fetch(:random_members, (0.1 * @population_size).ceil)
      @fitness_goal = options.fetch(:fitness_goal)
      @fitness_objective = options.fetch(:fitness_objective, :nullify) # :nullify, :maximize, :minimize
      @generations_limit = options.fetch(:generations_limit, 0)
      @evolution_types = options.fetch(:evolution_types, DEFAULT_EVOLUTION_TYPES)
      @members = options.fetch(:starting_members, [])
      @generation = 0 # initial population is generation 0
      @use_threads = options.fetch(:use_threads, false)
      @history = []

      build_population(@population_size)
    end

    def build_population(population_size)
      (population_size - @members.size).times do |i|
        @members << build_member
      end
      @history << members
    end

    def evolve!
      # Don't check best member if it's a start
      until generation > 0 && evolution_over?
        make_next_generation!
      end
    end

    def set_members_fitness!(fitness_values)
      throw "Invaid number of fitness values for population size" if fitness_values.size != members.size
      members.to_enum.each_with_index { |m, i| m.fitness = fitness_values[i] }
      sort_members
    end

    def make_next_generation!
      verify_population_size_is_positive!

      # Add some random members - to enrich mutations, etc
      random_members.times do
        @members << build_member
      end
      sort_members
      # @history << members

      selected_members = Marshal.load(Marshal.dump(members.first(population_selection)))
      remaining = Marshal.load(Marshal.dump(members.last(members.length - population_selection)))
      new_members = []

      counter = 0
      until (counter += 1) > population_size || new_members.length >= population_selection
        m1 = weighted_select
        m2 = weighted_select

        new_members += Marshal.load(Marshal.dump(apply_pairwise_evolutions(m1, m2)))
        new_members.uniq!
        # puts new_members.size
      end

      puts "Crossing finished."

      # In the case of an odd population size, we likely added one too many members.
      new_members.pop if new_members.length > population_selection

      # Save best members and their variations into reserved slots (population_selection)
      @members = (selected_members + apply_non_pairwise_evolutions(Marshal.load(Marshal.dump(selected_members + new_members))))
      @members.uniq!
      sort_members
      @members = @members.first(population_selection)

      mutated_remaining = apply_non_pairwise_evolutions(Marshal.load(Marshal.dump(remaining)))
      @members += remaining + mutated_remaining
      @members.uniq!
      # puts @members.inspect
      until @members.length >= population_size
        @members << build_member
      end
      
      # puts @members.inspect
      sort_members

      puts "!!!!!!!!!!!!!!",@members.size, remaining.size
      # Leave either original from remaining or its mutated version
      remaining.each.with_index do |m, i|
        if m != mutated_remaining[i]
          if m.fitness > mutated_remaining[i].fitness
            @members.delete m
          else
            @members.delete mutated_remaining[i]
          end
        end
      end
      puts @members.size
      
      @members = members.first(population_size)
      @history << members
      @generation += 1
    end

    def evolution_over?
      # check if the fitness goal or generation limit has been met
      if generations_limit > 0
        generation == generations_limit || goal_attained?
      else
        goal_attained?
      end
    end

    def best_member
      @members.first
    end

    def best_of_all_time x = 1
      @history.flatten.uniq{|a| a.genotypes.values}.sort{ |m| m.fitness}.reverse[0..(x-1)]
    end

    def best_each_generation
      @history.map(&:first)
    end

    def size
      @members.length
    end

    def organism_klass
      real_organism = @organism
      fitness_function = @fitness_function
      klass = Class.new(Darwinning::Organism) do
        @name = real_organism.name
        real_organism.try(:set_options, @organism_options)
        real_organism.try(:generate_geneset)
        @genes = real_organism.genes
      end
    end

    private

    def goal_attained?
      case @fitness_objective
      when :nullify
        best_member.fitness.abs <= fitness_goal
      when :maximize
        best_member.fitness >= fitness_goal
      else
        best_member.fitness <= fitness_goal
      end
    end

    def sort_members
      fitness_hash = {}
      fitness_array = []
      puts "use_threads = #{use_threads}"
      b = Benchmark.measure do
        if use_threads
          begin
            puts 'Starting threads'
            threads = Queue.new
            semaphore = Mutex.new
            fitness_array = ::Parallel.map(@members) do |m|
            # fitness_array = ::Parallel.map(@members.in_groups_of(4, false), in_processes: 12) do |mm|
              # puts mm.size
              # ::Parallel.map(mm, in_threads: 4) do |m|
                f = nil
                # @members.each do |m|
                # threads << Thread.new do
                sleep 0.001
                # puts "Starting thread in #{Parallel.worker_number} ..."
                # todo: use separate logger for thread
                ActiveRecord::Base.connection_pool.with_connection do |conn|
                  f = m.fitness(self)
                  # semaphore.synchronize {
                  #   fitness_hash[m] = f
                  # }
                end
                # puts "Finished thread ..."
                # end
                sleep 0.01
                [m, f]
              # end #Parallel
            end #Parallel
            # fitness_array = fitness_array.flatten
            # threads_a = []
            # while threads.size > 0 do
            #   threads_a << threads.pop(true)
            # end
            # threads_a.each(&:join)
          ensure
            # raise ::Parallel::Kill
            # threads_a.each{ |t| t.kill rescue nil }
          end
          # byebug
          fitness_hash = fitness_array.to_h
          # fitness_hash = fitness_array.reduce(:+).to_h # map{ |f, m| [m, f] }.to_h
          # @members.each.with_index do |m, index|
          #   fitness_hash[m] = fitness_array[index]
          # end
        else
          @members.each do |m|
            fitness_hash[m] = m.fitness(self)
          end
        end
      end
      puts "Fitness calculation took #{b.real} seconds (#{@members.size} members)"
      # byebug
      # puts fitness_hash.inspect
      case @fitness_objective
      when :nullify
        @members = @members.sort_by { |m| fitness_hash[m] ? fitness_hash[m].abs : fitness_hash[m] }
      when :maximize
        @members = @members.sort_by { |m| fitness_hash[m] }.reverse
      else
        @members = @members.sort_by { |m| fitness_hash[m] }
      end
      puts "Sorted."
    end

    def verify_population_size_is_positive!
      unless @population_size.positive?
        raise "Population size must be a positive number!"
      end
    end

    def build_member
      member = nil
      counter = 0
      until member&.valid?
        # puts (counter+=1)
        member = organism.new(@organism_options)
        unless member.class < Darwinning::Organism
          member.class.genes.each do |gene|
            gene_expression = gene.express
            member.send("#{gene.name}=", gene_expression)
          end
        end
      end
      member
    end

    def compute_normalized_fitness(membs=members)
      normalized_fitness = nil
      return membs.collect { |m| [1.0/membs.length, m] } if membs.first.fitness == membs.last.fitness
      if @fitness_objective == :nullify
        normalized_fitness = membs.collect { |m| [ m.fitness.abs <= fitness_goal ? Float::INFINITY : 1.0/(m.fitness.abs - fitness_goal), m] }
      else
        if @fitness_objective == :maximize
          if fitness_goal == Float::INFINITY then
            #assume goal to be at twice the maximum distance between fitness
            goal = membs.first.fitness + ( membs.first.fitness - membs.last.fitness )
          else
            goal = fitness_goal
          end
          normalized_fitness  = membs.collect { |m| [ m.fitness >= goal ? Float::INFINITY : 1.0/(goal - m.fitness), m] }
        else
          if fitness_goal == -Float::INFINITY then
            goal = membs.first.fitness - ( membs.last.fitness - membs.first.fitness )
          else
            goal = fitness_goal
          end
          normalized_fitness  = membs.collect { |m| [ m.fitness <= goal ? Float::INFINITY : 1.0/(m.fitness - goal), m] }
        end
      end
      if normalized_fitness.first[0] == Float::INFINITY then
        normalized_fitness.collect! { |m|
          m[0] == Float::INFINITY ? [1.0, m[1]] : [0.0, m[1]]
        }
      end
      sum = normalized_fitness.collect(&:first).inject(0.0, :+)
      normalized_fitness.collect { |m| [m[0]/sum, m[1]] }
    end

    def weighted_select(membs=members)
      normalized_fitness = compute_normalized_fitness
      normalized_cumulative_sums = []
      normalized_cumulative_sums[0] = normalized_fitness[0]
      (1...normalized_fitness.length).each { |i|
        normalized_cumulative_sums[i] = [ normalized_cumulative_sums[i-1][0] + normalized_fitness[i][0], normalized_fitness[i][1] ]
      }

      normalized_cumulative_sums.last[0] = 1.0
      cut = rand
      return normalized_cumulative_sums.find { |e| cut < e[0] }[1]
    end

    def apply_pairwise_evolutions(m1, m2)
      evolution_types.inject([m1, m2]) do |ret, evolution_type|
        if evolution_type.pairwise?
          evolution_type.evolve(*ret)
        else
          ret
        end
      end
    end

    def apply_non_pairwise_evolutions(members)
      evolution_types.inject(members) do |ret, evolution_type|
        if evolution_type.pairwise?
          ret
        else
          evolution_type.evolve(ret)
        end
      end
    end

  end
end
