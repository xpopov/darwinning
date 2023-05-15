require_relative 'darwinning/gene'
require_relative 'darwinning/organism'
require_relative 'darwinning/evolution_types/mutation'
require_relative 'darwinning/evolution_types/reproduction'
require_relative 'darwinning/population'
require_relative 'darwinning/config'
require_relative 'darwinning/monkey_patch'


module Darwinning
  extend Config

  def self.included(base)
    def base.genes
      gene_ranges.map { |k,v| Gene.new(name: k, value_range: v) }
    end

    def base.build_population(fitness_goal, population_size = 10, generations_limit = 100,
                         evolution_types = Population::DEFAULT_EVOLUTION_TYPES)
      Population.new(organism: self, population_size: population_size,
                     generations_limit: generations_limit, fitness_goal: fitness_goal,
                     evolution_types: evolution_types)
    end

    def base.is_evolveable?
      has_gene_ranges? &&
      gene_ranges.is_a?(Hash) &&
      gene_ranges.any? &&
      valid_genes? &&
      has_fitness_method?
    end

    private

    def base.has_gene_ranges?
      # self.constants.include?(:GENE_RANGES)
      self.instance_methods.include?(:possible_genes)
    end

    def base.has_fitness_method?
      self.instance_methods.include?(:fitness)
    end

    def base.gene_ranges
      self::GENE_RANGES
    end

    def base.valid_genes?
      genes.each do |gene|
        return false unless self.method_defined? gene.name
      end
      true
    end
  end

  def genes
    self.class.genes
  end

  def genotypes
    gt = {}
    genes.each do |gene|
      gt[gene] = self.send(gene.name)
    end
    gt
  end
end
