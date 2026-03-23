import Foundation

struct TemplateField {
    let key: String
    let labelKey: String
    let required: Bool
}

struct AIWriterTemplate {
    let id: String
    let emoji: String
    let nameKey: String
    let promptKey: String
    let suggestedTone: String
    let fields: [TemplateField]
}

let aiWriterTemplates: [AIWriterTemplate] = [
    AIWriterTemplate(
        id: "job_reply",
        emoji: "\u{1F4BC}",
        nameKey: "template.job_reply",
        promptKey: "template.job_reply.prompt",
        suggestedTone: "professional",
        fields: [
            TemplateField(key: "key_points", labelKey: "template.job_reply.field_key_points", required: true)
        ]
    ),
    AIWriterTemplate(
        id: "meeting_reschedule",
        emoji: "\u{1F4C5}",
        nameKey: "template.meeting_reschedule",
        promptKey: "template.meeting_reschedule.prompt",
        suggestedTone: "polished",
        fields: [
            TemplateField(key: "original_time", labelKey: "template.meeting.field_original_time", required: true),
            TemplateField(key: "new_time", labelKey: "template.meeting.field_new_time", required: true),
            TemplateField(key: "reason", labelKey: "template.meeting.field_reason", required: false)
        ]
    ),
    AIWriterTemplate(
        id: "apology",
        emoji: "\u{1F64F}",
        nameKey: "template.apology",
        promptKey: "template.apology.prompt",
        suggestedTone: "apologetic",
        fields: [
            TemplateField(key: "what_happened", labelKey: "template.apology.field_what_happened", required: true),
            TemplateField(key: "convey", labelKey: "template.apology.field_convey", required: false)
        ]
    ),
    AIWriterTemplate(
        id: "thank_you",
        emoji: "\u{1F64F}",
        nameKey: "template.thank_you",
        promptKey: "template.thank_you.prompt",
        suggestedTone: "friendly",
        fields: [
            TemplateField(key: "what_they_did", labelKey: "template.thankyou.field_what_they_did", required: true),
            TemplateField(key: "specific_detail", labelKey: "template.thankyou.field_detail", required: false)
        ]
    ),
    AIWriterTemplate(
        id: "birthday",
        emoji: "\u{1F382}",
        nameKey: "template.birthday",
        promptKey: "template.birthday.prompt",
        suggestedTone: "enthusiastic",
        fields: [
            TemplateField(key: "person", labelKey: "template.birthday.field_person", required: true),
            TemplateField(key: "personal_touch", labelKey: "template.birthday.field_personal_touch", required: false)
        ]
    ),
    AIWriterTemplate(
        id: "complaint",
        emoji: "\u{1F4DD}",
        nameKey: "template.complaint",
        promptKey: "template.complaint.prompt",
        suggestedTone: "confident",
        fields: [
            TemplateField(key: "issue", labelKey: "template.complaint.field_issue", required: true),
            TemplateField(key: "target", labelKey: "template.complaint.field_target", required: true),
            TemplateField(key: "desired_outcome", labelKey: "template.complaint.field_outcome", required: false)
        ]
    ),
    AIWriterTemplate(
        id: "follow_up",
        emoji: "\u{1F504}",
        nameKey: "template.follow_up",
        promptKey: "template.follow_up.prompt",
        suggestedTone: "professional",
        fields: [
            TemplateField(key: "previous", labelKey: "template.followup.field_previous", required: true),
            TemplateField(key: "topic", labelKey: "template.followup.field_topic", required: true),
            TemplateField(key: "next_steps", labelKey: "template.followup.field_next_steps", required: false)
        ]
    ),
    AIWriterTemplate(
        id: "cold_outreach",
        emoji: "\u{1F44B}",
        nameKey: "template.cold_outreach",
        promptKey: "template.cold_outreach.prompt",
        suggestedTone: "persuasive",
        fields: [
            TemplateField(key: "person_role", labelKey: "template.outreach.field_person", required: true),
            TemplateField(key: "purpose", labelKey: "template.outreach.field_purpose", required: true),
            TemplateField(key: "value_prop", labelKey: "template.outreach.field_value", required: false)
        ]
    ),
    AIWriterTemplate(
        id: "dating",
        emoji: "\u{1F495}",
        nameKey: "template.dating",
        promptKey: "template.dating.prompt",
        suggestedTone: "witty",
        fields: [
            TemplateField(key: "profile_detail", labelKey: "template.dating.field_profile", required: true),
            TemplateField(key: "shared_interest", labelKey: "template.dating.field_interest", required: false)
        ]
    ),
    AIWriterTemplate(
        id: "social_caption",
        emoji: "\u{1F4F8}",
        nameKey: "template.social_caption",
        promptKey: "template.social_caption.prompt",
        suggestedTone: "social",
        fields: [
            TemplateField(key: "post_about", labelKey: "template.caption.field_about", required: true),
            TemplateField(key: "mood", labelKey: "template.caption.field_mood", required: false),
            TemplateField(key: "platform", labelKey: "template.caption.field_platform", required: false)
        ]
    ),
    AIWriterTemplate(
        id: "rsvp",
        emoji: "\u{2709}\u{FE0F}",
        nameKey: "template.rsvp",
        promptKey: "template.rsvp.prompt",
        suggestedTone: "friendly",
        fields: [
            TemplateField(key: "event", labelKey: "template.rsvp.field_event", required: true),
            TemplateField(key: "attending", labelKey: "template.rsvp.field_attending", required: true),
            TemplateField(key: "message", labelKey: "template.rsvp.field_message", required: false)
        ]
    ),
    AIWriterTemplate(
        id: "congratulations",
        emoji: "\u{1F389}",
        nameKey: "template.congratulations",
        promptKey: "template.congratulations.prompt",
        suggestedTone: "enthusiastic",
        fields: [
            TemplateField(key: "person", labelKey: "template.congrats.field_person", required: true),
            TemplateField(key: "achievement", labelKey: "template.congrats.field_achievement", required: true),
            TemplateField(key: "personal_note", labelKey: "template.congrats.field_note", required: false)
        ]
    ),
]
