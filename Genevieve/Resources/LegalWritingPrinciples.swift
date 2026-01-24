import Foundation

/// Legal writing principles that Genevieve can reference in commentary
/// Organized by document type and writing aspect
enum LegalWritingPrinciples {

    // MARK: - Core Principles

    struct Principle: Identifiable {
        let id: String
        let name: String
        let description: String
        let examples: [String]
        let applicableDocTypes: Set<DocumentType>

        enum DocumentType: String, CaseIterable {
            case brief = "Brief"
            case motion = "Motion"
            case memo = "Memo"
            case contract = "Contract"
            case email = "Email"
            case letter = "Letter"
            case pleading = "Pleading"
            case discovery = "Discovery"
            case all = "All"
        }
    }

    // MARK: - Structure Principles

    static let structure: [Principle] = [
        Principle(
            id: "irac",
            name: "IRAC Structure",
            description: "Issue, Rule, Application, Conclusion - the foundational framework for legal analysis.",
            examples: [
                "State the issue clearly before diving into the rule",
                "Synthesize the governing rule from multiple authorities",
                "Apply facts to each element of the rule",
                "State your conclusion with confidence"
            ],
            applicableDocTypes: [.memo, .brief, .motion]
        ),
        Principle(
            id: "topic_sentences",
            name: "Strong Topic Sentences",
            description: "Each paragraph should begin with a sentence that telegraphs the argument to follow.",
            examples: [
                "Lead with your conclusion, then support it",
                "The reader should understand your point before the supporting details",
                "Topic sentences create a roadmap when read in sequence"
            ],
            applicableDocTypes: [.brief, .motion, .memo, .all]
        ),
        Principle(
            id: "one_idea",
            name: "One Idea Per Paragraph",
            description: "Each paragraph should focus on a single point or element. Multiple ideas dilute impact.",
            examples: [
                "If you find yourself using 'additionally' mid-paragraph, consider splitting",
                "Long paragraphs often contain multiple ideas fighting for attention",
                "Short, focused paragraphs are easier to skim and remember"
            ],
            applicableDocTypes: [.all]
        ),
        Principle(
            id: "signposting",
            name: "Signposting",
            description: "Guide readers through your argument with clear transitions and structural markers.",
            examples: [
                "Use headings liberally in longer documents",
                "Transition words like 'First,' 'Moreover,' and 'Finally' orient the reader",
                "Refer back to your roadmap: 'As discussed above...'"
            ],
            applicableDocTypes: [.brief, .motion, .memo]
        ),
        Principle(
            id: "frontloading",
            name: "Frontloading",
            description: "Put the most important information first - in sentences, paragraphs, and documents.",
            examples: [
                "Start with your strongest argument",
                "Lead sentences with the subject and verb, not qualifiers",
                "The first paragraph should tell the reader what to expect"
            ],
            applicableDocTypes: [.all]
        )
    ]

    // MARK: - Persuasion Principles

    static let persuasion: [Principle] = [
        Principle(
            id: "rule_synthesis",
            name: "Rule Synthesis",
            description: "Weave multiple authorities into a coherent rule statement before applying it.",
            examples: [
                "Don't just cite cases - extract and combine their holdings",
                "Show how different cases contribute to the same principle",
                "A synthesized rule is more persuasive than case-by-case analysis"
            ],
            applicableDocTypes: [.brief, .motion, .memo]
        ),
        Principle(
            id: "concrete_facts",
            name: "Concrete Over Abstract",
            description: "Specific facts persuade more than abstract assertions. Show, don't tell.",
            examples: [
                "'The defendant waited three months' beats 'unreasonable delay'",
                "Use numbers, dates, and specific details",
                "Abstract adjectives like 'egregious' are weak without factual support"
            ],
            applicableDocTypes: [.brief, .motion, .all]
        ),
        Principle(
            id: "counterarguments",
            name: "Address Counterarguments",
            description: "Anticipate and defuse opposing arguments. Ignoring them appears evasive.",
            examples: [
                "Acknowledge the strongest counterargument explicitly",
                "Frame concessions as strengths: 'While Defendant correctly notes X, this supports our position because...'",
                "Place counterargument sections strategically - not first, not last"
            ],
            applicableDocTypes: [.brief, .motion]
        ),
        Principle(
            id: "analogical_reasoning",
            name: "Analogical Reasoning",
            description: "Draw explicit parallels between your facts and favorable precedent.",
            examples: [
                "'Like the plaintiff in Smith who [specific facts], Plaintiff here [parallel facts]'",
                "Highlight factual similarities that matter to the legal rule",
                "Distinguish unfavorable cases on their facts"
            ],
            applicableDocTypes: [.brief, .motion, .memo]
        ),
        Principle(
            id: "theory_of_case",
            name: "Theory of the Case",
            description: "Every brief should tell a coherent story. The law follows from the narrative.",
            examples: [
                "Your theme should be expressible in one sentence",
                "Facts should build toward an inevitable legal conclusion",
                "The reader should feel the outcome is just"
            ],
            applicableDocTypes: [.brief, .motion]
        )
    ]

    // MARK: - Clarity Principles

    static let clarity: [Principle] = [
        Principle(
            id: "active_voice",
            name: "Active Voice",
            description: "Prefer active constructions. They are clearer and more direct.",
            examples: [
                "'Defendant breached the contract' not 'The contract was breached by Defendant'",
                "Passive voice obscures the actor and weakens assertions",
                "Use passive deliberately when the actor is unknown or unimportant"
            ],
            applicableDocTypes: [.all]
        ),
        Principle(
            id: "plain_language",
            name: "Plain Language",
            description: "Use simple, direct language. Complexity does not equal sophistication.",
            examples: [
                "'Because' not 'due to the fact that'",
                "'Now' not 'at this point in time'",
                "Avoid Latin unless necessary for precision"
            ],
            applicableDocTypes: [.all]
        ),
        Principle(
            id: "sentence_length",
            name: "Varied Sentence Length",
            description: "Mix short and long sentences. Long sentences lose readers. Short ones punch.",
            examples: [
                "Average sentence length should be 20-25 words",
                "No sentence should exceed 40 words",
                "Use short sentences for emphasis after complex analysis"
            ],
            applicableDocTypes: [.all]
        ),
        Principle(
            id: "defined_terms",
            name: "Consistent Terminology",
            description: "Use the same term for the same concept throughout. Variation creates confusion.",
            examples: [
                "If you call it 'the Agreement' once, don't switch to 'the Contract'",
                "Define terms parenthetically on first use",
                "Avoid elegant variation - precision trumps style"
            ],
            applicableDocTypes: [.all]
        )
    ]

    // MARK: - Contract-Specific Principles

    static let contracts: [Principle] = [
        Principle(
            id: "precision_drafting",
            name: "Precision in Drafting",
            description: "Every word matters. Ambiguity invites litigation.",
            examples: [
                "Use 'shall' for obligations, 'may' for permissions",
                "Define all capitalized terms",
                "Specify time periods with precision: 'within 30 days' not 'promptly'"
            ],
            applicableDocTypes: [.contract]
        ),
        Principle(
            id: "complete_coverage",
            name: "Complete Coverage",
            description: "Address all foreseeable scenarios. Silence creates gaps.",
            examples: [
                "What happens if a deadline falls on a weekend?",
                "Who bears risk during the gap between signing and closing?",
                "What constitutes proper notice?"
            ],
            applicableDocTypes: [.contract]
        ),
        Principle(
            id: "risk_allocation",
            name: "Clear Risk Allocation",
            description: "Make explicit who bears each risk. Don't leave it to implication.",
            examples: [
                "Indemnification provisions should specify scope and process",
                "Limitation of liability clauses need clear triggers",
                "Force majeure should list specific events"
            ],
            applicableDocTypes: [.contract]
        )
    ]

    // MARK: - All Principles

    static var all: [Principle] {
        structure + persuasion + clarity + contracts
    }

    // MARK: - Lookup

    /// Find principles relevant to a document type and writing aspect
    static func principles(
        for documentType: String,
        section: String? = nil
    ) -> [Principle] {
        let docType = Principle.DocumentType(rawValue: documentType) ?? .all

        return all.filter { principle in
            principle.applicableDocTypes.contains(.all) ||
            principle.applicableDocTypes.contains(docType)
        }
    }

    /// Get a random principle suitable for a teaching moment
    static func randomPrinciple(for documentType: String) -> Principle? {
        let applicable = principles(for: documentType)
        return applicable.randomElement()
    }

    /// Format a principle for inclusion in commentary
    static func formatForCommentary(_ principle: Principle) -> String {
        var output = "**\(principle.name)**: \(principle.description)"
        if let example = principle.examples.randomElement() {
            output += " (\(example))"
        }
        return output
    }

    // MARK: - Context-Aware Selection

    /// Select principles based on detected writing patterns
    static func suggestPrinciples(
        basedOn patterns: [String],
        documentType: String
    ) -> [Principle] {
        var suggestions: [Principle] = []

        let patternsLower = patterns.map { $0.lowercased() }

        // Long paragraphs -> One idea per paragraph
        if patternsLower.contains(where: { $0.contains("long paragraph") }) {
            if let principle = all.first(where: { $0.id == "one_idea" }) {
                suggestions.append(principle)
            }
        }

        // Passive voice detected
        if patternsLower.contains(where: { $0.contains("passive") }) {
            if let principle = all.first(where: { $0.id == "active_voice" }) {
                suggestions.append(principle)
            }
        }

        // Weak topic sentences
        if patternsLower.contains(where: { $0.contains("topic sentence") || $0.contains("unclear opening") }) {
            if let principle = all.first(where: { $0.id == "topic_sentences" }) {
                suggestions.append(principle)
            }
        }

        // Abstract language
        if patternsLower.contains(where: { $0.contains("abstract") || $0.contains("vague") }) {
            if let principle = all.first(where: { $0.id == "concrete_facts" }) {
                suggestions.append(principle)
            }
        }

        // Missing transitions
        if patternsLower.contains(where: { $0.contains("transition") || $0.contains("flow") }) {
            if let principle = all.first(where: { $0.id == "signposting" }) {
                suggestions.append(principle)
            }
        }

        // If no specific matches, return a random applicable principle
        if suggestions.isEmpty {
            if let random = randomPrinciple(for: documentType) {
                suggestions.append(random)
            }
        }

        return suggestions
    }
}
