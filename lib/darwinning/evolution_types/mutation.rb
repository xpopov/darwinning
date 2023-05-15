module Darwinning
  module EvolutionTypes

    class Mutation
      attr_reader :mutation_rate

      def initialize(options = {})
        @mutation_rate = options.fetch(:mutation_rate, 0.0)
      end

      def evolve(members)
        mutate(members)
      end

      def pairwise?
        false
      end

      protected

      def mutate(members)
        members.map do |member|
          # Run mutation for every gene
          member.genes.each do |gene|
            if rand < mutation_rate
              member = re_express_random_genotype(member)
            end
          end
          member
        end
      end

      # Selects a random genotype from the organism and re-expresses its gene
      def re_express_random_genotype(member)
        random_index = rand(member.genotypes.length)
        gene = member.genes[random_index]

        value = gene.express
        if member.class.superclass == Darwinning::Organism
          # puts "Mutate #{gene.name} = #{value}"
          member.genotypes[gene.name] = value
        else
          member.send("#{gene.name}=", value)
        end
        # puts member.to_s

        member
      end
    end

  end
end
