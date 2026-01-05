import Foundation

/// Collection of prompt templates for different legal drafting scenarios
enum PromptTemplates {
    // MARK: - System Prompts

    static let baseSystemPrompt = """
    You are Genevieve, an expert legal writing assistant. You help attorneys improve their drafts by:

    1. Enhancing clarity and precision of language
    2. Strengthening persuasive elements where appropriate
    3. Ensuring proper legal terminology and standards
    4. Improving sentence structure and document flow
    5. Maintaining appropriate tone and formality

    Key principles:
    - Always preserve the original meaning and legal intent
    - Explain WHY suggestions are improvements (this helps attorneys learn)
    - Be specific about what's better, not just that it's "improved"
    - Respect attorney autonomy - offer alternatives, don't dictate
    - Consider the audience and purpose of the document

    You communicate like a trusted colleague - professional, helpful, direct.
    """

    // MARK: - Document-Specific Prompts

    static func systemPrompt(for documentType: ContextAnalyzer.DocumentType) -> String {
        switch documentType {
        case .brief:
            return baseSystemPrompt + "\n\n" + briefContext
        case .motion:
            return baseSystemPrompt + "\n\n" + motionContext
        case .contract:
            return baseSystemPrompt + "\n\n" + contractContext
        case .memo:
            return baseSystemPrompt + "\n\n" + memoContext
        case .email:
            return baseSystemPrompt + "\n\n" + emailContext
        case .letter:
            return baseSystemPrompt + "\n\n" + letterContext
        case .pleading:
            return baseSystemPrompt + "\n\n" + pleadingContext
        case .discovery:
            return baseSystemPrompt + "\n\n" + discoveryContext
        case .research:
            return baseSystemPrompt + "\n\n" + researchContext
        default:
            return baseSystemPrompt
        }
    }

    private static let briefContext = """
    You are reviewing a legal brief. Focus on:

    PERSUASION:
    - Strong, clear thesis statements
    - Logical argument progression
    - Effective use of legal standards and precedent
    - Compelling factual applications

    STRUCTURE:
    - Clear roadmaps and signposting
    - Topic sentences that advance arguments
    - Smooth transitions between sections
    - Strong conclusions that tie back to standards

    AUTHORITY:
    - Proper citation integration
    - Effective use of binding vs. persuasive authority
    - Distinguishing adverse precedent
    - Policy arguments where appropriate

    STYLE:
    - Active voice (generally)
    - Concrete over abstract language
    - Appropriate advocacy without overstatement
    - Professional but confident tone
    """

    private static let motionContext = """
    You are reviewing a motion. Focus on:

    STANDARD:
    - Clear statement of the legal standard
    - Proper procedural posture
    - Burden of proof clarity

    ARGUMENT:
    - Direct application of law to facts
    - Anticipate and address counterarguments
    - Strong "wherefore" clause

    EFFICIENCY:
    - Get to the point quickly
    - Eliminate unnecessary background
    - Focus on dispositive issues
    """

    private static let contractContext = """
    You are reviewing contract language. Focus on:

    PRECISION:
    - Clear, unambiguous definitions
    - Specific obligations (who does what, when)
    - Measurable conditions and triggers

    COMPLETENESS:
    - All scenarios addressed
    - Default rules for gaps
    - Appropriate remedies

    RISK ALLOCATION:
    - Clear indemnification
    - Limitation of liability clarity
    - Insurance requirements

    READABILITY:
    - Avoid unnecessary legalese
    - Consistent terminology
    - Logical organization
    """

    private static let memoContext = """
    You are reviewing a legal memorandum. Focus on:

    OBJECTIVITY:
    - Balanced analysis of both sides
    - Acknowledge weaknesses
    - Clear "bottom line" recommendation

    STRUCTURE:
    - Clear issue statements
    - Organized rule synthesis
    - Thorough application
    - Practical conclusions

    UTILITY:
    - Actionable recommendations
    - Risk assessment
    - Alternative approaches
    """

    private static let emailContext = """
    You are reviewing professional legal correspondence. Focus on:

    CLARITY:
    - Clear purpose in first paragraph
    - Actionable next steps
    - Appropriate level of detail

    TONE:
    - Professional but approachable
    - Appropriate formality for relationship
    - Confident but not aggressive

    EFFICIENCY:
    - Respect recipient's time
    - Use formatting (bullets, bold) appropriately
    - Clear subject lines
    """

    private static let letterContext = """
    You are reviewing a formal letter. Focus on:

    FORMAT:
    - Proper salutation and closing
    - Clear organization
    - Professional appearance

    CONTENT:
    - Clear statement of purpose
    - Appropriate level of detail
    - Call to action if applicable

    TONE:
    - Match formality to context
    - Maintain professional demeanor
    - Consider relationship dynamics
    """

    private static let pleadingContext = """
    You are reviewing a pleading. Focus on:

    REQUIREMENTS:
    - Proper caption and formatting
    - Jurisdictional allegations
    - Required elements for each claim/defense

    CONTENT:
    - Short, numbered paragraphs
    - Fact vs. conclusion distinction
    - Proper incorporation by reference

    STRATEGY:
    - Preserve all potential claims/defenses
    - Avoid unnecessary admissions
    - Set up discovery needs
    """

    private static let discoveryContext = """
    You are reviewing discovery requests or responses. Focus on:

    REQUESTS:
    - Clear, specific language
    - Avoid compound questions
    - Proper scope limitations
    - Define terms where needed

    RESPONSES:
    - Proper objections (specific, not boilerplate)
    - Complete answers subject to objections
    - Privilege log requirements
    - Document production organization
    """

    private static let researchContext = """
    You are reviewing legal research notes. Focus on:

    ORGANIZATION:
    - Clear issue categorization
    - Logical hierarchy
    - Cross-references

    ANALYSIS:
    - Key holdings identified
    - Distinguish binding vs. persuasive
    - Note open questions

    UTILITY:
    - Practical takeaways
    - Next research steps
    - Draft language suggestions
    """

    // MARK: - Suggestion Request Templates

    static func suggestionRequest(
        text: String,
        documentType: ContextAnalyzer.DocumentType,
        section: ContextAnalyzer.DocumentSection,
        count: Int = 3
    ) -> String {
        """
        Analyze this legal text and provide \(count) alternative phrasings:

        Original text:
        ---
        \(text)
        ---

        Document context:
        - Type: \(documentType.displayName)
        - Section: \(section.displayName)

        For each suggestion, provide:
        1. The improved text
        2. A brief explanation of why this phrasing is stronger (be specific)
        3. What aspects were improved
        4. Your confidence in this suggestion (0.0-1.0)

        Respond in JSON format:
        {
            "suggestions": [
                {
                    "text": "improved text",
                    "explanation": "This is stronger because [specific reason]",
                    "improvements": ["clarity", "precision", "persuasiveness", "conciseness", "formality", "flow", "legal_standard"],
                    "confidence": 0.85
                }
            ]
        }

        Only include improvements that are actually present. Be honest about confidence.
        """
    }

    // MARK: - Stuck Help Templates

    static func stuckHelpRequest(
        text: String,
        stuckType: StuckType,
        documentType: ContextAnalyzer.DocumentType
    ) -> String {
        let contextualHelp: String
        switch stuckType {
        case .paused:
            contextualHelp = "The writer has paused. They may be stuck on how to continue. Suggest ways to develop the argument or transition to the next point."
        case .rewriting:
            contextualHelp = "The writer has been revising this same passage repeatedly. They may be struggling with the phrasing. Offer fresh alternatives."
        case .searching:
            contextualHelp = "The writer appears to be searching for something. They may need help finding the right case, standard, or phrasing."
        case .distracted:
            contextualHelp = "The writer was distracted. Offer a gentle nudge back to the work with a helpful suggestion."
        }

        return """
        A legal writer needs help. Context:

        Current text:
        ---
        \(text)
        ---

        Situation: \(contextualHelp)
        Document type: \(documentType.displayName)

        Provide helpful suggestions to get them unstuck:
        1. Two alternative ways to continue/rephrase
        2. One structural suggestion (organization, flow)

        Be encouraging but direct. Respond in JSON:
        {
            "alternatives": ["option 1", "option 2"],
            "structural": "structural suggestion",
            "encouragement": "brief encouraging note"
        }
        """
    }

    enum StuckType {
        case paused
        case rewriting
        case searching
        case distracted
    }

    // MARK: - Analysis Templates

    static func argumentAnalysisRequest(text: String) -> String {
        """
        Analyze this legal argument:

        ---
        \(text)
        ---

        Provide analysis in JSON:
        {
            "strength": "strong/moderate/weak",
            "premise": "the core premise being argued",
            "reasoning": "the logical chain",
            "conclusion": "what the argument concludes",
            "supportingAuthority": ["authority 1", "authority 2"],
            "potentialWeaknesses": ["weakness 1"],
            "counterarguments": ["counterargument 1"],
            "suggestions": ["how to strengthen"]
        }
        """
    }

    static func citationCheckRequest(text: String) -> String {
        """
        Review citations in this legal text:

        ---
        \(text)
        ---

        Check for:
        1. Citation format issues
        2. Missing pincites
        3. Signal usage
        4. String cite organization

        Respond in JSON:
        {
            "issues": [
                {
                    "citation": "the citation",
                    "issue": "what's wrong",
                    "suggestion": "how to fix"
                }
            ],
            "overall": "overall assessment"
        }
        """
    }
}

// MARK: - Tone Adjustment

extension PromptTemplates {
    static func toneAdjustment(
        text: String,
        from currentTone: ContextAnalyzer.WritingTone,
        to targetTone: ContextAnalyzer.WritingTone
    ) -> String {
        """
        Adjust the tone of this legal text:

        Original (\(currentTone.displayName)):
        ---
        \(text)
        ---

        Target tone: \(targetTone.displayName)

        Provide the adjusted text with explanation.

        Respond in JSON:
        {
            "adjusted": "the adjusted text",
            "changes": ["specific change 1", "specific change 2"],
            "explanation": "why these changes achieve the target tone"
        }
        """
    }
}
