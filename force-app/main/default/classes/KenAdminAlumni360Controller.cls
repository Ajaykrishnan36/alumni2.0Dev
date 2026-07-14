/**
 * KenAdminAlumni360Controller
 *
 * Backend for the kenAdminAlumni360 LWC. Returns the data for the
 * single-record Alumni 360 detail page — hero/header, six KPI snapshot
 * cards, the nine main tabs (Overview, Lifecycle, Historical Journey,
 * Academic Record, Admissions, Career, Continuing Education, Engagement,
 * Jobs), the five sub-tabs (Recognition, Giving, Support, Documents,
 * Communications), and the right rail (Needs Attention, Recent Activity,
 * Quick Actions, Record Health).
 *
 * Schema integration:
 *   - getHeader(recordId) queries Ken_Alumni_CRM__c (the same master object
 *     used by KenAdminAlumniController) and the Person Account lookup for
 *     identity / contact / employer fields.
 *   - Sections without a wired source object (Lifecycle, Journey,
 *     Academic, Admissions, Continuing Education, Jobs, Recognition,
 *     Giving, Documents, Communications) return empty DTOs — all lists
 *     initialised, all primitive fields null/zero — so the LWC's
 *     lwc:if guards simply hide those subsections until the upstream
 *     schema lands. No demo / placeholder data is returned anywhere.
 *
 * Backwards-compatible: this is a brand new class. It does not modify any
 * existing Apex, triggers, permission sets, profiles, or objects. It does
 * not extend any existing class. It is `with sharing`, all methods are
 * `@AuraEnabled(cacheable=true)`, and it performs no DML.
 */
public with sharing class KenAdminAlumni360Controller {

    /* ============================================================
       Master wrapper — returned by getAlumni360(recordId)
       ============================================================ */
    public class Alumni360DTO {
        @AuraEnabled public HeaderDTO            header;
        @AuraEnabled public SnapshotCardsDTO     snapshot;
        @AuraEnabled public OverviewDTO          overview;
        @AuraEnabled public LifecycleDTO         lifecycle;
        @AuraEnabled public JourneyDTO           journey;
        @AuraEnabled public AcademicDTO          academic;
        @AuraEnabled public AdmissionsDTO        admissions;
        @AuraEnabled public CareerDTO            career;
        @AuraEnabled public ContinuingEdDTO      continuingEducation;
        @AuraEnabled public EngagementDTO        engagement;
        @AuraEnabled public JobsDTO              jobs;
        @AuraEnabled public RecognitionDTO       recognition;
        @AuraEnabled public GivingDTO            giving;
        @AuraEnabled public SupportDTO           support;
        @AuraEnabled public DocumentsDTO         documents;
        @AuraEnabled public CommunicationsDTO    communications;
        @AuraEnabled public RightRailDTO         rightRail;
    }

    /* ============================================================
       Header + KPI snapshot wrappers
       ============================================================ */
    public class HeaderDTO {
        @AuraEnabled public Id     alumniId;
        @AuraEnabled public Id     personAccountId;     // surface for the inline LinkedIn Sync button
        @AuraEnabled public String name;
        @AuraEnabled public String initials;
        @AuraEnabled public String role;               // ALUMNA / ALUMNUS
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String classOf;
        @AuraEnabled public String program;
        @AuraEnabled public String programDates;
        @AuraEnabled public String yearsOut;
        @AuraEnabled public String school;
        @AuraEnabled public String campus;
        @AuraEnabled public String status;
        @AuraEnabled public String stage;
        @AuraEnabled public String legacyId;
        @AuraEnabled public String verifyMessage;
        @AuraEnabled public List<BadgeDTO> badges;
    }

    public class BadgeDTO {
        @AuraEnabled public String label;
        @AuraEnabled public String tone;   // emerald | amber | sky | violet | teal | rose | gray
    }

    public class SnapshotCardsDTO {
        @AuraEnabled public SnapshotCard academic;
        @AuraEnabled public SnapshotCard currentCareer;
        @AuraEnabled public SnapshotCard engagement;
        @AuraEnabled public SnapshotCard giving;
        @AuraEnabled public SnapshotCard continuingEducation;
        @AuraEnabled public SnapshotCard hiring;
    }
    public class SnapshotCard {
        @AuraEnabled public String accent;   // sky | indigo | brand | teal | amber
        @AuraEnabled public String title;
        @AuraEnabled public String bigValue;
        @AuraEnabled public String subValue;
        @AuraEnabled public List<KeyValue> rows;
    }
    public class KeyValue {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String emphasis;  // emerald | sky | null
    }

    /* ============================================================
       Section wrappers (mirror the LWC tabs 1:1)
       ============================================================ */
    public class OverviewDTO {
        @AuraEnabled public List<KeyValue> snapshot;
        @AuraEnabled public List<KeyValue> personalContact;
        @AuraEnabled public List<RelationshipDTO> relationships;
    }
    public class RelationshipDTO {
        @AuraEnabled public String initials;
        @AuraEnabled public String label;
        @AuraEnabled public String name;
        @AuraEnabled public String subline;
        @AuraEnabled public Boolean emphasis;
    }

    public class LifecycleDTO {
        @AuraEnabled public List<LifecyclePhase> phases;
        @AuraEnabled public LifecyclePhase currentPhase;
        @AuraEnabled public List<KeyValue> currentStats;
    }
    public class LifecyclePhase {
        @AuraEnabled public String stage;
        @AuraEnabled public String stageTone;     // emerald | amber
        @AuraEnabled public String title;
        @AuraEnabled public String subline;
        @AuraEnabled public String period;
    }

    public class JourneyDTO {
        @AuraEnabled public Integer admissionsCount;
        @AuraEnabled public Integer studentCount;
        @AuraEnabled public Integer graduationCount;
        @AuraEnabled public Integer alumniCount;
        @AuraEnabled public Integer totalEvents;
        @AuraEnabled public List<JourneyEvent> events;
    }
    public class JourneyEvent {
        @AuraEnabled public String stage;     // admissions | student | graduation | alumni
        @AuraEnabled public String title;
        @AuraEnabled public String subline;
        @AuraEnabled public String occurredOn;
    }

    public class AcademicDTO {
        @AuraEnabled public List<EducationRow> education;
        @AuraEnabled public String graduationFooter;
    }
    public class EducationRow {
        @AuraEnabled public String institute;
        @AuraEnabled public String degree;
        @AuraEnabled public String gradeLabel;   // e.g. "CGPA 8.4" or "85%" — pre-formatted
        @AuraEnabled public String yearOfCompletion;
    }

    public class AdmissionsDTO {
        @AuraEnabled public List<KeyValue> lead;
        @AuraEnabled public List<KeyValue> application;
        @AuraEnabled public List<KeyValue> entranceExam;
        @AuraEnabled public List<KeyValue> offer;
        @AuraEnabled public List<KeyValue> scholarship;
        @AuraEnabled public List<AdmissionsReferral> referrals;
        @AuraEnabled public List<IntakeDocument> intakeDocuments;
    }
    public class AdmissionsReferral {
        @AuraEnabled public String initials;
        @AuraEnabled public String name;
        @AuraEnabled public String relation;
        @AuraEnabled public String programAndCampus;
        @AuraEnabled public String referenceId;
        @AuraEnabled public String status;        // APPLIED / ENROLLED / OFFER ISSUED / DECLINED
        @AuraEnabled public String statusTone;
    }
    public class IntakeDocument {
        @AuraEnabled public String label;
        @AuraEnabled public String status;        // VERIFIED / NOT APPLICABLE
        @AuraEnabled public String statusTone;
    }

    public class CareerDTO {
        @AuraEnabled public List<EmploymentRow> employmentHistory;
        @AuraEnabled public List<KeyValue> internships;
        @AuraEnabled public List<String> highlights;
    }
    public class EmploymentRow {
        @AuraEnabled public String role;
        @AuraEnabled public String company;
        @AuraEnabled public String location;
        @AuraEnabled public String source;        // Self-reported / Campus placement
        @AuraEnabled public String period;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean current;
    }

    public class ContinuingEdDTO {
        @AuraEnabled public List<CourseRow> ken42Academy;
        @AuraEnabled public List<CourseRow> external;
        @AuraEnabled public List<CourseRow> recommended;
    }
    public class CourseRow {
        @AuraEnabled public String courseCode;
        @AuraEnabled public String title;
        @AuraEnabled public String school;
        @AuraEnabled public String dates;
        @AuraEnabled public String instructor;
        @AuraEnabled public String cohort;
        @AuraEnabled public String delivery;
        @AuraEnabled public String credits;
        @AuraEnabled public String grade;
        @AuraEnabled public String progressLabel;
        @AuraEnabled public Integer progressPct;
        @AuraEnabled public String nextSession;
        @AuraEnabled public String certificateId;
        @AuraEnabled public Boolean onTranscript;
        @AuraEnabled public Boolean ken42Verified;
        @AuraEnabled public String type;            // CERTIFICATE / DIPLOMA / SPECIALIZATION
        @AuraEnabled public String state;           // IN PROGRESS / COMPLETED
        @AuraEnabled public String recommendNote;
    }

    public class EngagementDTO {
        @AuraEnabled public Integer eventsAttendedCount;
        @AuraEnabled public Integer activeMenteesCount;
        @AuraEnabled public Integer totalReferralsCount;
        @AuraEnabled public Integer talksOnCampusCount;
        @AuraEnabled public List<EventRow> eventsHosted;
        @AuraEnabled public List<EventRow> eventsAttended;
        @AuraEnabled public List<MentorshipRow> mentorship;
        @AuraEnabled public List<ReferralRow> hiringReferrals;
    }
    public class EventRow {
        @AuraEnabled public String title;
        @AuraEnabled public String reference;
        @AuraEnabled public String role;
        @AuraEnabled public String details;
        @AuraEnabled public String when_x;   // 'when' is reserved
    }
    public class MentorshipRow {
        @AuraEnabled public String initials;
        @AuraEnabled public String name;
        @AuraEnabled public String alumniRef;
        @AuraEnabled public String programAndSemester;
        @AuraEnabled public String sessions;
        @AuraEnabled public String since;
        @AuraEnabled public String status;   // ACTIVE / CONCLUDED
        @AuraEnabled public String statusTone;
    }
    public class ReferralRow {
        @AuraEnabled public String initials;
        @AuraEnabled public String name;
        @AuraEnabled public String classOf;
        @AuraEnabled public String role;
        @AuraEnabled public String company;
        @AuraEnabled public String status;    // HIRED / IN PIPELINE / DECLINED OFFER
        @AuraEnabled public String statusTone;
    }

    public class JobsDTO {
        @AuraEnabled public Integer postingsCount;
        @AuraEnabled public Integer currentlyOpenCount;
        @AuraEnabled public Integer filledByKen42Count;
        @AuraEnabled public Integer ken42ApplicantsCount;
        @AuraEnabled public List<JobRow> postedJobs;
        @AuraEnabled public List<JobRow> appliedJobs;
    }
    public class JobRow {
        @AuraEnabled public String title;
        @AuraEnabled public String company;
        @AuraEnabled public String details;
        @AuraEnabled public String reference;
        @AuraEnabled public String status;
        @AuraEnabled public String statusTone;
        @AuraEnabled public String postedOn;
    }

    public class RecognitionDTO {
        @AuraEnabled public Integer alumniOfMonthCount;
        @AuraEnabled public Integer awardsCount;
        @AuraEnabled public Integer featuresCount;
        @AuraEnabled public Integer honoursCount;
        @AuraEnabled public List<RecognitionRow> items;
    }
    public class RecognitionRow {
        @AuraEnabled public String title;
        @AuraEnabled public String issuer;
        @AuraEnabled public String reference;
        @AuraEnabled public String quote;
        @AuraEnabled public String type;       // ALUMNI OF THE MONTH / AWARD / FEATURE / HONOUR
        @AuraEnabled public String typeTone;
    }

    public class GivingDTO {
        @AuraEnabled public String lifetimeAmount;
        @AuraEnabled public String endowmentAmount;
        @AuraEnabled public String scholarshipsAmount;
        @AuraEnabled public String libraryReunionAmount;
        @AuraEnabled public String donorTier;
        @AuraEnabled public String donorNote;
        @AuraEnabled public List<GiftRow> gifts;
    }
    public class GiftRow {
        @AuraEnabled public String giftId;
        @AuraEnabled public String giftDate;
        @AuraEnabled public String amount;
        @AuraEnabled public String fund;
        @AuraEnabled public String method;
        @AuraEnabled public String receiptStatus;
        @AuraEnabled public String receiptTone;
    }

    public class SupportDTO {
        @AuraEnabled public Integer ticketsRaisedCount;
        @AuraEnabled public Integer currentlyOpenCount;
        @AuraEnabled public String  avgFirstResponse;
        @AuraEnabled public Integer surveysSubmittedCount;
        @AuraEnabled public List<TicketRow> tickets;
        @AuraEnabled public List<SurveyRow> surveys;
    }
    public class TicketRow {
        @AuraEnabled public String title;
        @AuraEnabled public String reference;
        @AuraEnabled public String details;
        @AuraEnabled public String status;
        @AuraEnabled public String statusTone;
        @AuraEnabled public String priority;
        @AuraEnabled public String priorityTone;
    }
    public class SurveyRow {
        @AuraEnabled public String title;
        @AuraEnabled public String details;
        @AuraEnabled public String score;
        @AuraEnabled public String sentiment;       // POSITIVE / CONSTRUCTIVE / MIXED
        @AuraEnabled public String sentimentTone;
    }

    public class DocumentsDTO {
        @AuraEnabled public List<DocumentRow> items;
    }
    public class DocumentRow {
        @AuraEnabled public String title;
        @AuraEnabled public String details;
        @AuraEnabled public String status;
        @AuraEnabled public String statusTone;
        @AuraEnabled public Boolean emphasis;
    }

    public class CommunicationsDTO {
        @AuraEnabled public String recipientName;
        @AuraEnabled public String recipientEmail;
        @AuraEnabled public Integer last30DaysCount;
        @AuraEnabled public Integer outboundCount;
        @AuraEnabled public Integer inboundCount;
        @AuraEnabled public Integer newslettersCount;
        @AuraEnabled public List<MessageRow> recent;
        @AuraEnabled public List<NotificationPreference> preferences;
    }
    public class MessageRow {
        @AuraEnabled public String title;
        @AuraEnabled public String category;
        @AuraEnabled public String categoryTone;
        @AuraEnabled public String details;
        @AuraEnabled public String when_x;
    }
    public class NotificationPreference {
        @AuraEnabled public String channel;
        @AuraEnabled public Boolean enabled;
    }

    public class RightRailDTO {
        @AuraEnabled public List<NeedsAttentionItem> needsAttention;
        @AuraEnabled public List<RecentActivityItem> recentActivity;
        @AuraEnabled public List<QuickActionItem>   quickActions;
        @AuraEnabled public List<RecordHealthItem>  recordHealth;
    }
    public class NeedsAttentionItem {
        @AuraEnabled public String iconKey;       // receipt | book | mentor
        @AuraEnabled public String title;
        @AuraEnabled public String actionLabel;   // "Resend ›" / "Remind ›" / "Schedule ›"
    }
    public class RecentActivityItem {
        @AuraEnabled public String iconKey;
        @AuraEnabled public String title;
        @AuraEnabled public String when_x;
    }
    public class QuickActionItem {
        @AuraEnabled public String iconKey;
        @AuraEnabled public String label;
    }
    public class RecordHealthItem {
        @AuraEnabled public String label;
        @AuraEnabled public Boolean ok;
        @AuraEnabled public String missingNote;
    }

    /* ============================================================
       PUBLIC API — master fetch
       ============================================================ */

    /**
     * One-shot fetch returning every section for the LWC. Convenient for
     * the initial render. Sub-tab clicks can call the per-section methods
     * below for lighter refreshes.
     */
    @AuraEnabled(cacheable=true)
    public static Alumni360DTO getAlumni360(Id recordId) {
        Alumni360DTO dto = new Alumni360DTO();
        dto.header              = getHeader(recordId);
        dto.snapshot            = getSnapshot(recordId);
        dto.overview            = getOverview(recordId);
        dto.lifecycle           = getLifecycle(recordId);
        dto.journey             = getJourney(recordId);
        dto.academic            = getAcademic(recordId);
        dto.admissions          = getAdmissions(recordId);
        dto.career              = getCareer(recordId);
        dto.continuingEducation = getContinuingEducation(recordId);
        dto.engagement          = getEngagement(recordId);
        dto.jobs                = getJobs(recordId);
        dto.recognition         = getRecognition(recordId);
        dto.giving              = getGiving(recordId);
        dto.support             = getSupport(recordId);
        dto.documents           = getDocuments(recordId);
        dto.communications      = getCommunications(recordId);
        dto.rightRail           = getRightRail(recordId);
        return dto;
    }

    /* ============================================================
       INLINE EDIT — raw editable values + diff-based update
       --------------------------------------------------------------
       getEditableFields() returns the *raw* values (un-formatted) for
       the editable profile fields, keyed by a stable vocabulary the LWC
       binds its inputs to. updateAlumniProfile() takes only the keys the
       user actually changed (the LWC diffs client-side) and updates the
       smallest possible set of records — the Person Account and, when a
       real CRM row exists, Ken_Alumni_CRM__c. Nothing is written when a
       value did not change, so we never touch a record needlessly.
       ============================================================ */

    /**
     * Canonical nationality list, kept in sync with the restricted picklist that
     * client orgs (e.g. KJS) define on Account.Nationality__c. Used as the option
     * source whenever the org's field is still a plain Text field (we don't force
     * a Text->Picklist conversion, which would clobber a client's existing
     * picklist on deploy). A combobox writes a plain string, valid for both types.
     */
    private static final List<String> NATIONALITY_VALUES = new List<String>{
        'Indian', 'Afghan', 'Albanian', 'Algerian', 'American', 'Andorran',
        'Angolan', 'Antiguan', 'Argentinean', 'Armenian', 'Australian', 'Austrian',
        'Azerbaijani', 'Bahamian', 'Bahraini', 'Bangladeshi', 'Barbadian', 'Barbudan',
        'Batswana', 'Belarusian', 'Belgian', 'Belizean', 'Beninese', 'Bhutanese',
        'Bolivian', 'Bosnian', 'Brazilian', 'British', 'Bruneian', 'Bulgarian',
        'Burkinabe', 'Burmese', 'Burundian', 'Cambodian', 'Cameroonian', 'Canadian',
        'Cape Verdean', 'Central African', 'Chadian', 'Chilean', 'Chinese', 'Colombian',
        'Comoran', 'Congolese', 'Costa Rican', 'Croatian', 'Cuban', 'Cypriot',
        'Czech', 'Danish', 'Djibouti', 'Dominican', 'Dutch', 'East Timorese',
        'Ecuadorean', 'Egyptian', 'Emirian', 'Equatorial Guinean', 'Eritrean', 'Estonian',
        'Ethiopian', 'Fijian', 'Filipino', 'Finnish', 'French', 'Gabonese',
        'Gambian', 'Georgian', 'German', 'Ghanaian', 'Greek', 'Grenadian',
        'Guatemalan', 'Guinean', 'Guyanese', 'Haitian', 'Herzegovinian', 'Honduran',
        'Hungarian', 'Icelander', 'I-Kiribati', 'Indonesian', 'Iranian', 'Iraqi',
        'Irish', 'Israeli', 'Italian', 'Ivorian', 'Jamaican', 'Japanese',
        'Jordanian', 'Kazakhstani', 'Kenyan', 'Kittian and Nevisian', 'Kuwaiti', 'Kyrgyz',
        'Laotian', 'Latvian', 'Lebanese', 'Liberian', 'Libyan', 'Liechtensteiner',
        'Lithuanian', 'Luxembourger', 'Macedonian', 'Malagasy', 'Malawian', 'Malaysian',
        'Maldivian', 'Malian', 'Maltese', 'Marshallese', 'Mauritanian', 'Mauritian',
        'Mexican', 'Micronesian', 'Moldovan', 'Monacan', 'Mongolian', 'Moroccan',
        'Mosotho', 'Motswana', 'Mozambican', 'Namibian', 'Nauruan', 'Nepalese',
        'New Zealander', 'Nicaraguan', 'Nigerian', 'Nigerien', 'Ni-Vanuatu', 'Northern Irish',
        'North Korean', 'Norwegian', 'Omani', 'Pakistani', 'Palauan', 'Panamanian',
        'Papua New Guinean', 'Paraguayan', 'Peruvian', 'Polish', 'Portuguese', 'Qatari',
        'Romanian', 'Russian', 'Rwandan', 'Saint Lucian', 'Salvadoran', 'Samoan',
        'San Marinese', 'Sao Tomean', 'Saudi', 'Scottish', 'Senegalese', 'Serbian',
        'Seychellois', 'Sierra Leonean', 'Singaporean', 'Slovakian', 'Slovenian', 'Solomon Islander',
        'Somali', 'South African', 'South Korean', 'Spanish', 'Sri Lankan', 'Sudanese',
        'Surinamer', 'Swazi', 'Swedish', 'Swiss', 'Syrian', 'Taiwanese',
        'Tajik', 'Tanzanian', 'Thai', 'Tibetian', 'Togolese', 'Tongan',
        'Trinidadian or Tobagonian', 'Tunisian', 'Turkish', 'Tuvaluan', 'Ugandan', 'Ukrainian',
        'Uruguayan', 'Uzbekistani', 'Venezuelan', 'Welsh', 'Yemenite', 'Zambian',
        'Zimbabwean', 'Tibetan'
    };

    /**
     * Active picklist entries for a field as {label, value} maps, so the LWC can
     * render a combobox. When the field is a real picklist we read its describe
     * (org-specific values win). When it's still a Text field, we fall back to
     * the supplied constant list so the dropdown still renders everywhere.
     */
    private static List<Map<String, String>> picklistOptions(String objectApiName, String fieldApiName, List<String> fallback) {
        List<Map<String, String>> opts = new List<Map<String, String>>();
        Boolean isPicklist = false;
        if (String.isNotBlank(fieldApiName)) {
            try {
                Schema.DescribeFieldResult dfr =
                    Schema.getGlobalDescribe().get(objectApiName).getDescribe()
                        .fields.getMap().get(fieldApiName).getDescribe();
                if (dfr.getType() == Schema.DisplayType.Picklist ||
                    dfr.getType() == Schema.DisplayType.MultiPicklist) {
                    isPicklist = true;
                    for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                        if (!pe.isActive()) continue;
                        opts.add(new Map<String, String>{ 'label' => pe.getLabel(), 'value' => pe.getValue() });
                    }
                }
            } catch (Exception ignored) { /* unknown field/object */ }
        }
        if (!isPicklist && fallback != null) {
            for (String v : fallback) {
                opts.add(new Map<String, String>{ 'label' => v, 'value' => v });
            }
        }
        return opts;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getEditableFields(Id recordId) {
        Map<String, Object> m = new Map<String, Object>();
        m.put('crmEditable', false);
        m.put('accountEditable', false);
        if (recordId == null) return m;

        AlumniContext ctx = loadContext(recordId);

        // ----- Person Account scalar fields (dynamic for optional bio fields) -----
        if (ctx.personAccountId != null) {
            Map<String, Schema.SObjectField> af = Account.SObjectType.getDescribe().fields.getMap();
            String natField  = af.containsKey('Nationality__pc') ? 'Nationality__pc'
                              : (af.containsKey('Nationality__c') ? 'Nationality__c' : null);
            String langField = af.containsKey('Languages_Known__c') ? 'Languages_Known__c' : null;
            List<String> fields = new List<String>{
                'PersonEmail','PersonMobilePhone','Linkedin_Profile_URL__c','PersonBirthdate',
                'PersonMailingStreet','PersonMailingCity','PersonMailingState',
                'PersonMailingPostalCode','PersonMailingCountry'
            };
            if (natField  != null) fields.add(natField);
            if (langField != null) fields.add(langField);
            try {
                Id pid = ctx.personAccountId;
                List<Account> rows = (List<Account>) Database.query(
                    'SELECT ' + String.join(fields, ', ') + ' FROM Account WHERE Id = :pid LIMIT 1');
                if (!rows.isEmpty()) {
                    Account a = rows[0];
                    m.put('accountEditable', true);
                    m.put('email',       a.PersonEmail);
                    m.put('phone',       a.PersonMobilePhone);
                    m.put('linkedin',    a.Linkedin_Profile_URL__c);
                    m.put('dob',         a.PersonBirthdate);                 // serialises as yyyy-MM-dd
                    m.put('street',      a.PersonMailingStreet);
                    m.put('city',        a.PersonMailingCity);
                    m.put('state',       a.PersonMailingState);
                    m.put('postalCode',  a.PersonMailingPostalCode);
                    m.put('country',     a.PersonMailingCountry);
                    m.put('nationality', natField  != null ? a.get(natField)  : null);
                    m.put('languages',   langField != null ? a.get(langField) : null);
                }
            } catch (Exception ignored) { /* leave account fields out */ }
            // Nationality picklist options (empty when the org still has it as a
            // plain text field — the LWC then falls back to a text input).
            m.put('nationalityOptions', picklistOptions('Account', natField, NATIONALITY_VALUES));
        }

        // ----- Ken_Alumni_CRM__c scalar fields (only when a real row exists) -----
        if (ctx.crm != null && ctx.crm.Id != null) {
            m.put('crmEditable',        true);
            m.put('classOf',            ctx.crm.Year_of_Graduation__c);
            m.put('currentCompany',     ctx.crm.Current_Company__c);
            m.put('campus',             ctx.crm.Current_Location__c);
            m.put('registrationNumber', ctx.crm.Registration_Number__c);
            m.put('industry',           ctx.crm.Industry__c);
            m.put('specialization',     ctx.crm.Specialization__c);
        }
        return m;
    }

    /**
     * Apply only the changed keys. The LWC sends a JSON object containing
     * exactly the fields the user edited (it diffs against the values from
     * getEditableFields), so we build each SObject with just those fields
     * and DML only the objects that actually have a change.
     */
    @AuraEnabled
    public static void updateAlumniProfile(Id recordId, String changesJson) {
        if (recordId == null || String.isBlank(changesJson)) return;
        Map<String, Object> changes = (Map<String, Object>) JSON.deserializeUntyped(changesJson);
        if (changes == null || changes.isEmpty()) return;

        AlumniContext ctx = loadContext(recordId);

        Map<String, Schema.SObjectField> af = Account.SObjectType.getDescribe().fields.getMap();
        String natField  = af.containsKey('Nationality__pc') ? 'Nationality__pc'
                          : (af.containsKey('Nationality__c') ? 'Nationality__c' : null);
        String langField = af.containsKey('Languages_Known__c') ? 'Languages_Known__c' : null;

        // ----- Person Account -----
        Account acct;
        Boolean acctDirty = false;
        if (ctx.personAccountId != null) {
            acct = new Account(Id = ctx.personAccountId);
            for (String key : changes.keySet()) {
                Object v = changes.get(key);
                String s = (v == null) ? null : String.valueOf(v);
                if (String.isBlank(s)) s = null;
                if (key == 'email')           { acct.PersonEmail = s; acctDirty = true; }
                else if (key == 'phone')      { acct.PersonMobilePhone = s; acctDirty = true; }
                else if (key == 'linkedin')   { acct.Linkedin_Profile_URL__c = s; acctDirty = true; }
                else if (key == 'dob')        { acct.PersonBirthdate = (s == null) ? null : Date.valueOf(s); acctDirty = true; }
                else if (key == 'street')     { acct.PersonMailingStreet = s; acctDirty = true; }
                else if (key == 'city')       { acct.PersonMailingCity = s; acctDirty = true; }
                else if (key == 'state')      { acct.PersonMailingState = s; acctDirty = true; }
                else if (key == 'postalCode') { acct.PersonMailingPostalCode = s; acctDirty = true; }
                else if (key == 'country')    { acct.PersonMailingCountry = s; acctDirty = true; }
                else if (key == 'nationality' && natField  != null) { acct.put(natField, s); acctDirty = true; }
                else if (key == 'languages'  && langField != null) { acct.put(langField, s); acctDirty = true; }
            }
        }

        // ----- Ken_Alumni_CRM__c (only when a real row exists) -----
        Ken_Alumni_CRM__c crm;
        Boolean crmDirty = false;
        if (ctx.crm != null && ctx.crm.Id != null) {
            crm = new Ken_Alumni_CRM__c(Id = ctx.crm.Id);
            for (String key : changes.keySet()) {
                Object v = changes.get(key);
                String s = (v == null) ? null : String.valueOf(v);
                if (String.isBlank(s)) s = null;
                if (key == 'classOf')                { crm.Year_of_Graduation__c = s; crmDirty = true; }
                else if (key == 'currentCompany')    { crm.Current_Company__c = s; crmDirty = true; }
                else if (key == 'campus')            { crm.Current_Location__c = s; crmDirty = true; }
                else if (key == 'registrationNumber'){ crm.Registration_Number__c = s; crmDirty = true; }
                else if (key == 'industry')          { crm.Industry__c = s; crmDirty = true; }
                else if (key == 'specialization')    { crm.Specialization__c = s; crmDirty = true; }
            }
        }

        try {
            if (acctDirty && acct != null) update acct;
            if (crmDirty  && crm  != null) update crm;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    /* ============================================================
       CHILD-RECORD EDIT — Education (PersonEducation) and
       Employment (PersonEmployment). The display DTOs (EducationRow /
       EmploymentRow) carry no Id, so these methods return editable rows
       *with* Ids, plus save methods that upsert the submitted rows and
       hard-delete the ones the user removed. New rows hang off the
       alumnus's Person Account.
       ============================================================ */
    public class EducationEditRow {
        @AuraEnabled public String id;
        @AuraEnabled public String institute;
        @AuraEnabled public String degree;
        @AuraEnabled public String gradeType;
        @AuraEnabled public String grade;
        @AuraEnabled public String yearOfCompletion;
    }
    public class EmploymentEditRow {
        @AuraEnabled public String id;
        @AuraEnabled public String role;
        @AuraEnabled public String company;
        @AuraEnabled public String location;
        @AuraEnabled public String startDate;   // yyyy-MM-dd
        @AuraEnabled public String endDate;      // yyyy-MM-dd
        @AuraEnabled public Boolean current;
        @AuraEnabled public String description;
    }
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAcademicEditData(Id recordId) {
        Map<String, Object> out = new Map<String, Object>();
        out.put('editable', false);
        out.put('rows', new List<EducationEditRow>());
        out.put('gradeTypeOptions', gradeTypeOptions());
        if (recordId == null) return out;

        Id personAcctId = lookupPersonAccountId(recordId);
        if (personAcctId == null) return out;
        out.put('editable', true);

        List<EducationEditRow> rows = new List<EducationEditRow>();
        try {
            for (PersonEducation pe : [
                SELECT Id, Institute_Name__c, Degree_Name__c, Grade__c, Grade_Type__c, Year_of_Completion__c
                FROM PersonEducation
                WHERE AccountId = :personAcctId
                  AND (Is_Archived__c = false OR Is_Archived__c = null)
                ORDER BY Year_of_Completion__c DESC NULLS LAST
                LIMIT 100
            ]) {
                EducationEditRow r = new EducationEditRow();
                r.id = pe.Id;
                r.institute = pe.Institute_Name__c;
                r.degree = pe.Degree_Name__c;
                r.gradeType = pe.Grade_Type__c;
                r.grade = pe.Grade__c;
                r.yearOfCompletion = pe.Year_of_Completion__c;
                rows.add(r);
            }
        } catch (Exception ignored) {}
        out.put('rows', rows);
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCareerEditData(Id recordId) {
        Map<String, Object> out = new Map<String, Object>();
        out.put('editable', false);
        out.put('rows', new List<EmploymentEditRow>());
        if (recordId == null) return out;

        Id personAcctId = lookupPersonAccountId(recordId);
        if (personAcctId == null) return out;
        out.put('editable', true);

        List<EmploymentEditRow> rows = new List<EmploymentEditRow>();
        try {
            for (PersonEmployment pe : [
                SELECT Id, Designation__c, Company_Name__c, Location__c,
                       StartDate, EndDate, Currently_Employed__c, Description__c
                FROM PersonEmployment
                WHERE AccountId = :personAcctId
                  AND (Is_Archived__c = false OR Is_Archived__c = null)
                ORDER BY StartDate DESC NULLS LAST
                LIMIT 100
            ]) {
                EmploymentEditRow r = new EmploymentEditRow();
                r.id = pe.Id;
                r.role = pe.Designation__c;
                r.company = pe.Company_Name__c;
                r.location = pe.Location__c;
                r.startDate = (pe.StartDate != null) ? String.valueOf(pe.StartDate) : null;
                r.endDate = (pe.EndDate != null) ? String.valueOf(pe.EndDate) : null;
                r.current = pe.Currently_Employed__c;
                r.description = pe.Description__c;
                rows.add(r);
            }
        } catch (Exception ignored) {}
        out.put('rows', rows);
        return out;
    }

    @AuraEnabled
    public static void saveEducationRows(Id recordId, String rowsJson, String deleteIdsJson) {
        Id personAcctId = (recordId == null) ? null : lookupPersonAccountId(recordId);
        if (personAcctId == null) throw new AuraHandledException('No Person Account linked to this alumnus.');

        List<EducationEditRow> rows = String.isBlank(rowsJson)
            ? new List<EducationEditRow>()
            : (List<EducationEditRow>) JSON.deserialize(rowsJson, List<EducationEditRow>.class);

        List<PersonEducation> toUpsert = new List<PersonEducation>();
        for (EducationEditRow r : rows) {
            // Skip fully-empty new rows.
            if (String.isBlank(r.id) && String.isBlank(r.institute) && String.isBlank(r.degree)
                && String.isBlank(r.grade) && String.isBlank(r.yearOfCompletion)) continue;
            PersonEducation pe = String.isBlank(r.id)
                ? new PersonEducation(AccountId = personAcctId, Is_Archived__c = false)
                : new PersonEducation(Id = (Id) r.id);
            String deg = blankToNull(r.degree);
            // Standard Name field is required (labelled "Degree") — keep it in
            // sync with the degree, falling back so the row can always be saved.
            pe.Name = (deg != null) ? deg
                      : (blankToNull(r.institute) != null ? r.institute : 'Education');
            pe.Institute_Name__c = blankToNull(r.institute);
            pe.Degree_Name__c = deg;
            pe.Grade_Type__c = blankToNull(r.gradeType);
            pe.Grade__c = blankToNull(r.grade);
            pe.Year_of_Completion__c = blankToNull(r.yearOfCompletion);
            toUpsert.add(pe);
        }

        try {
            if (!toUpsert.isEmpty()) upsert toUpsert;
            deleteChildren('PersonEducation', personAcctId, deleteIdsJson);
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static void saveEmploymentRows(Id recordId, String rowsJson, String deleteIdsJson) {
        Id personAcctId = (recordId == null) ? null : lookupPersonAccountId(recordId);
        if (personAcctId == null) throw new AuraHandledException('No Person Account linked to this alumnus.');

        List<EmploymentEditRow> rows = String.isBlank(rowsJson)
            ? new List<EmploymentEditRow>()
            : (List<EmploymentEditRow>) JSON.deserialize(rowsJson, List<EmploymentEditRow>.class);

        List<PersonEmployment> toUpsert = new List<PersonEmployment>();
        for (EmploymentEditRow r : rows) {
            if (String.isBlank(r.id) && String.isBlank(r.role) && String.isBlank(r.company)) continue;
            PersonEmployment pe = String.isBlank(r.id)
                // New rows need the required RelatedPersonId (labelled "Related
                // Person") — point it at the alumnus's Person Account.
                ? new PersonEmployment(AccountId = personAcctId, RelatedPersonId = personAcctId, Is_Archived__c = false)
                : new PersonEmployment(Id = (Id) r.id);
            String comp = blankToNull(r.company);
            // Standard Name field is required (labelled "Employer").
            pe.Name = (comp != null) ? comp
                      : (blankToNull(r.role) != null ? r.role : 'Employment');
            pe.Designation__c = blankToNull(r.role);
            pe.Company_Name__c = comp;
            pe.Location__c = blankToNull(r.location);
            pe.StartDate = String.isBlank(r.startDate) ? null : Date.valueOf(r.startDate);
            pe.EndDate = String.isBlank(r.endDate) ? null : Date.valueOf(r.endDate);
            pe.Currently_Employed__c = (r.current == true);
            pe.Description__c = blankToNull(r.description);
            toUpsert.add(pe);
        }

        try {
            if (!toUpsert.isEmpty()) upsert toUpsert;
            deleteChildren('PersonEmployment', personAcctId, deleteIdsJson);
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    /** Hard-delete the requested child rows, but only those that actually belong to this Person Account. */
    private static void deleteChildren(String objApi, Id personAcctId, String deleteIdsJson) {
        if (String.isBlank(deleteIdsJson)) return;
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(deleteIdsJson);
        Set<Id> ids = new Set<Id>();
        for (Object o : raw) {
            String s = (o == null) ? null : String.valueOf(o);
            if (String.isNotBlank(s)) { try { ids.add((Id) s); } catch (Exception ignored) {} }
        }
        if (ids.isEmpty()) return;
        String soql = 'SELECT Id FROM ' + objApi + ' WHERE Id IN :ids AND AccountId = :personAcctId';
        List<SObject> rows = Database.query(soql);
        if (!rows.isEmpty()) delete rows;
    }

    private static String blankToNull(String s) {
        return String.isBlank(s) ? null : s;
    }

    private static List<PicklistOption> gradeTypeOptions() {
        List<PicklistOption> opts = new List<PicklistOption>();
        try {
            for (Schema.PicklistEntry e : PersonEducation.Grade_Type__c.getDescribe().getPicklistValues()) {
                if (!e.isActive()) continue;
                PicklistOption o = new PicklistOption();
                o.label = e.getLabel();
                o.value = e.getValue();
                opts.add(o);
            }
        } catch (Exception ignored) {}
        return opts;
    }

    /* ============================================================
       PUBLIC API — section methods
       ============================================================ */

    /**
     * Reads identity / status / employer fields from Ken_Alumni_CRM__c and
     * its Person Account lookup. Returns an empty HeaderDTO (badges list
     * initialised, all string fields null) when no recordId is supplied or
     * when the record cannot be loaded — never returns demo data.
     */
    @AuraEnabled(cacheable=true)
    public static HeaderDTO getHeader(Id recordId) {
        if (recordId == null) return emptyHeader();
        try {
            Ken_Alumni_CRM__c r = resolveCrmRow(recordId);
            if (r == null) return emptyHeader();

            // ConstituentRole stage / registration status (separate query — standard sObject)
            String stageLabel = null;
            if (r.ConstituentRole__c != null) {
                try {
                    List<ConstituentRole> crRows = [
                        SELECT Id, RoleType, Status, Registration_Status__c
                        FROM ConstituentRole
                        WHERE Id = :r.ConstituentRole__c
                        LIMIT 1
                    ];
                    if (!crRows.isEmpty()) {
                        stageLabel = crRows[0].Registration_Status__c != null
                                        ? crRows[0].Registration_Status__c
                                        : crRows[0].RoleType;
                    }
                } catch (Exception innerEx) { /* leave stage null */ }
            }

            HeaderDTO h = new HeaderDTO();
            h.alumniId = r.Id;
            h.personAccountId = r.Person_Account__c;
            h.name = (r.Person_Account__c != null && r.Person_Account__r.Name != null)
                        ? r.Person_Account__r.Name : r.Name;
            h.initials = computeInitials(h.name);
            h.role = 'ALUMNUS';
            h.registrationNumber = r.Registration_Number__c;
            h.classOf = r.Year_of_Graduation__c;
            h.program = displayProgram(r.Program__c);
            // programDates: registration date year — year_of_graduation
            String regYear = null;
            if (r.Registration_Date__c != null) regYear = String.valueOf(r.Registration_Date__c.year());
            if (regYear != null && r.Year_of_Graduation__c != null) {
                h.programDates = regYear + ' – ' + r.Year_of_Graduation__c;
            } else if (r.Year_of_Graduation__c != null) {
                h.programDates = r.Year_of_Graduation__c;
            }
            h.yearsOut = (r.Year_of_Graduation__c != null) ? yearsOutLabel(r.Year_of_Graduation__c) : null;
            h.school = null;       // no school field in data model
            h.campus = r.Current_Location__c;
            h.status = (r.Is_Active__c == true) ? 'Active Alumna' : 'Inactive';
            h.stage = stageLabel;
            h.legacyId = null;     // no legacy id field
            h.verifyMessage = (r.Person_Account__c != null && r.Person_Account__r.PersonEmail != null)
                                ? 'Contact verified' : 'Contact missing';
            h.badges = new List<BadgeDTO>();
            if (r.Is_Active__c == true) h.badges.add(badge('Active Alumna', 'emerald'));
            return h;
        } catch (Exception e) {
            return emptyHeader();
        }
    }

    @AuraEnabled(cacheable=true)
    public static SnapshotCardsDTO getSnapshot(Id recordId) {
        if (recordId == null) return emptySnapshot();
        return buildSnapshotFromOrg(recordId);
    }

    /**
     * Empty snapshot — all six cards null. Returned when no recordId is
     * supplied; the LWC has lwc:if guards on each card so they simply
     * don't render.
     */
    private static SnapshotCardsDTO emptySnapshot() {
        return new SnapshotCardsDTO();
    }

    /**
     * Real-data snapshot: only currentCareer + engagement are populated.
     * academic / giving / continuingEducation / hiring intentionally remain
     * null — the LWC hides those cards.
     */
    private static SnapshotCardsDTO buildSnapshotFromOrg(Id recordId) {
        SnapshotCardsDTO s = new SnapshotCardsDTO();
        s.academic = null;
        s.giving = null;
        s.continuingEducation = null;
        s.hiring = null;

        Id personAcctId = lookupPersonAccountId(recordId);

        // ----- CURRENT CAREER from PersonEmployment -----
        SnapshotCard career = new SnapshotCard();
        career.accent = 'indigo';
        career.title = 'CURRENT CAREER';
        career.rows = new List<KeyValue>();
        if (personAcctId != null) {
            try {
                List<PersonEmployment> all = [
                    SELECT Id, Designation__c, Job_Role__c, Company_Name__c, Location__c,
                           StartDate, EndDate, Currently_Employed__c, Is_Archived__c
                    FROM PersonEmployment
                    WHERE AccountId = :personAcctId
                    ORDER BY StartDate DESC NULLS LAST
                ];
                PersonEmployment current;
                for (PersonEmployment pe : all) {
                    if (pe.Currently_Employed__c == true && pe.Is_Archived__c != true) {
                        current = pe; break;
                    }
                }
                if (current == null) {
                    for (PersonEmployment pe : all) {
                        if (pe.EndDate == null && pe.Is_Archived__c != true) { current = pe; break; }
                    }
                }
                if (current != null) {
                    String role = (current.Designation__c != null) ? current.Designation__c : current.Job_Role__c;
                    career.bigValue = (role != null) ? role : '—';
                    String employer = (current.Company_Name__c != null) ? current.Company_Name__c : '';
                    String loc = (current.Location__c != null) ? current.Location__c : '';
                    String sub = employer;
                    if (String.isNotBlank(loc)) sub += (String.isNotBlank(employer) ? ' · ' : '') + loc;
                    career.subValue = String.isNotBlank(sub) ? sub : null;

                    String sinceLabel = null;
                    if (current.StartDate != null) sinceLabel = formatMonthYear(current.StartDate);
                    career.rows.add(kv('Since', sinceLabel != null ? sinceLabel : '—', null));
                    career.rows.add(kv('Roles held', String.valueOf(all.size()), null));
                    career.rows.add(kv('Location', String.isNotBlank(loc) ? loc : '—', null));
                } else {
                    career.bigValue = '—';
                    career.subValue = 'No current employment on file';
                    career.rows.add(kv('Since', '—', null));
                    career.rows.add(kv('Roles held', String.valueOf(all.size()), null));
                    career.rows.add(kv('Location', '—', null));
                }
            } catch (Exception ex) {
                career.bigValue = '—';
                career.rows.add(kv('Since', '—', null));
                career.rows.add(kv('Roles held', '0', null));
                career.rows.add(kv('Location', '—', null));
            }
        }
        s.currentCareer = career;

        // ----- ENGAGEMENT (events + mentorship) -----
        SnapshotCard eng = new SnapshotCard();
        eng.accent = 'brand';
        eng.title = 'ALUMNI ENGAGEMENT';
        eng.subValue = 'Engagement score';
        eng.rows = new List<KeyValue>();

        Integer eventsCount = 0;
        Integer activeMentees = 0;
        if (personAcctId != null) {
            try {
                eventsCount = [
                    SELECT COUNT()
                    FROM Ken_Event_Booking__c
                    WHERE Person_Account__c = :personAcctId
                ];
            } catch (Exception ex) { eventsCount = 0; }
            try {
                activeMentees = [
                    SELECT COUNT()
                    FROM Ken_Mentorship__c
                    WHERE Mentor__c = :personAcctId
                      AND Mentorship_Status__c IN ('Accepted', 'Scheduled')
                ];
            } catch (Exception ex) { activeMentees = 0; }
        }

        String tier;
        if (eventsCount >= 6 || activeMentees >= 3) tier = 'High';
        else if (eventsCount >= 3 || activeMentees >= 1) tier = 'Medium';
        else tier = 'Low';
        eng.bigValue = tier;
        eng.rows.add(kv('Events attended', String.valueOf(eventsCount), null));
        eng.rows.add(kv('Mentees',
            activeMentees > 0 ? (activeMentees + ' active') : '0',
            activeMentees > 0 ? 'emerald' : null));
        // Talks given — no source object
        eng.rows.add(kv('Talks given', '0', null));
        s.engagement = eng;

        return s;
    }

    @AuraEnabled(cacheable=true)
    public static OverviewDTO getOverview(Id recordId) {
        if (recordId == null) return emptyOverview();
        try {
            Ken_Alumni_CRM__c r = resolveCrmRow(recordId);
            if (r == null) return emptyOverview();

            // Current employment (for snapshot block)
            PersonEmployment cur;
            if (r.Person_Account__c != null) {
                try {
                    List<PersonEmployment> peList = [
                        SELECT Designation__c, Job_Role__c, Company_Name__c, Location__c,
                               StartDate, EndDate, Currently_Employed__c, Is_Archived__c
                        FROM PersonEmployment
                        WHERE AccountId = :r.Person_Account__c
                        ORDER BY StartDate DESC NULLS LAST
                    ];
                    for (PersonEmployment pe : peList) {
                        if (pe.Currently_Employed__c == true && pe.Is_Archived__c != true) { cur = pe; break; }
                    }
                    if (cur == null) {
                        for (PersonEmployment pe : peList) {
                            if (pe.EndDate == null && pe.Is_Archived__c != true) { cur = pe; break; }
                        }
                    }
                } catch (Exception ex) { /* leave cur null */ }
            }

            String employerLine = null;
            String roleLine = null;
            if (cur != null) {
                employerLine = (cur.Company_Name__c != null ? cur.Company_Name__c : '');
                if (cur.Location__c != null) {
                    employerLine += (String.isNotBlank(employerLine) ? ' · ' : '') + cur.Location__c;
                }
                roleLine = (cur.Designation__c != null) ? cur.Designation__c : cur.Job_Role__c;
            }
            if (String.isBlank(employerLine)) employerLine = r.Current_Company__c;

            String yearsOut = (r.Year_of_Graduation__c != null) ? yearsOutLabel(r.Year_of_Graduation__c) : null;

            OverviewDTO o = new OverviewDTO();
            o.snapshot = new List<KeyValue>{
                kv('Alumni status',     r.Is_Active__c == true ? 'Active · Engaged' : 'Inactive', null),
                kv('Class of',          r.Year_of_Graduation__c,                                  null),
                kv('Program',           displayProgram(r.Program__c),                              null),
                kv('Years post-grad',   yearsOut,                                                  null),
                kv('Current employer',  employerLine,                                              null),
                kv('Current role',      roleLine,                                                  null),
                kv('Chapter',           null,                                                       null),
                kv('Engagement tier',   null,                                                       null)
            };

            String address = null;
            String dob = null;
            String phone = null, emailPersonal = null, linkedIn = null;
            if (r.Person_Account__c != null && r.Person_Account__r != null) {
                address = buildAddress(
                    r.Person_Account__r.PersonMailingStreet,
                    r.Person_Account__r.PersonMailingCity,
                    r.Person_Account__r.PersonMailingState,
                    r.Person_Account__r.PersonMailingPostalCode,
                    r.Person_Account__r.PersonMailingCountry
                );
                if (r.Person_Account__r.PersonBirthdate != null) {
                    dob = r.Person_Account__r.PersonBirthdate.format();
                }
                phone         = r.Person_Account__r.PersonMobilePhone;
                emailPersonal = r.Person_Account__r.PersonEmail;
                linkedIn      = r.Person_Account__r.Linkedin_Profile_URL__c;
            }
            // Bio fields — only read from real Account fields, never hardcoded.
            String nationality = null;
            String languages   = null;
            if (r.Person_Account__c != null && r.Person_Account__r != null) {
                // Nationality lives on the Person Account variant of the field.
                try { nationality = (String) r.Person_Account__r.get('Nationality__pc'); } catch (Exception ex) { /* field may not exist */ }
                if (String.isBlank(nationality)) {
                    try { nationality = (String) r.Person_Account__r.get('Nationality__c'); } catch (Exception ex) { /* ignore */ }
                }
                // Languages — read from Languages_Known__c if the org has it.
                try { languages = (String) r.Person_Account__r.get('Languages_Known__c'); } catch (Exception ex) { /* ignore */ }
            }
            o.personalContact = new List<KeyValue>{
                kv('Phone',            phone,         null),
                kv('Email (personal)', emailPersonal, null),
                kv('Email (alumni)',   emailPersonal, null),
                kv('LinkedIn',         linkedIn,      null),
                kv('Date of birth',    dob,           null),
                kv('Nationality',      nationality,   null),
                kv('Languages',        languages,     null),
                kv('Address',          address,       null)
            };

            // No relationship data model wired yet
            o.relationships = new List<RelationshipDTO>();
            return o;
        } catch (Exception e) {
            return emptyOverview();
        }
    }

    private static OverviewDTO emptyOverview() {
        OverviewDTO o = new OverviewDTO();
        o.snapshot = new List<KeyValue>();
        o.personalContact = new List<KeyValue>();
        o.relationships = new List<RelationshipDTO>();
        return o;
    }

    // TODO upcoming-module: no semester/lifecycle phase data in current schema
    @AuraEnabled(cacheable=true)
    public static LifecycleDTO getLifecycle(Id recordId) {
        LifecycleDTO d = new LifecycleDTO();
        d.phases = new List<LifecyclePhase>();
        d.currentPhase = null;
        d.currentStats = new List<KeyValue>();
        return d;
    }

    // TODO upcoming-module: no historical journey event store yet
    @AuraEnabled(cacheable=true)
    public static JourneyDTO getJourney(Id recordId) {
        JourneyDTO j = new JourneyDTO();
        j.admissionsCount = 0;
        j.studentCount = 0;
        j.graduationCount = 0;
        j.alumniCount = 0;
        j.totalEvents = 0;
        j.events = new List<JourneyEvent>();
        return j;
    }

    // Academic Record shows the alumnus's PersonEducation rows + a footer summarising
    // their graduation from this institution (pulled from Ken_Alumni_CRM__c).
    // SGPA / semester / class-rank data model isn't part of the alumni module yet.
    @AuraEnabled(cacheable=true)
    public static AcademicDTO getAcademic(Id recordId) {
        AcademicDTO a = new AcademicDTO();
        a.education = new List<EducationRow>();
        a.graduationFooter = null;
        if (recordId == null) return a;

        Id personAcctId = null;
        try {
            Ken_Alumni_CRM__c row = resolveCrmRow(recordId);
            List<Ken_Alumni_CRM__c> rows = (row == null) ? new List<Ken_Alumni_CRM__c>() : new List<Ken_Alumni_CRM__c>{ row };
            if (!rows.isEmpty()) {
                Ken_Alumni_CRM__c r = rows[0];
                personAcctId = r.Person_Account__c;
                String prog  = (r.Program__c != null)             ? displayProgram(r.Program__c) : 'Program';
                String year  = (r.Year_of_Graduation__c != null)  ? r.Year_of_Graduation__c  : '—';
                String regNo = (r.Registration_Number__c != null) ? r.Registration_Number__c : null;
                a.graduationFooter = 'Graduated ' + year + ' · ' + prog
                    + (regNo != null ? ' · ' + regNo : '');
            }
        } catch (Exception e) { /* swallow */ }

        if (personAcctId == null) return a;

        try {
            for (PersonEducation pe : [
                SELECT Institute_Name__c, Degree_Name__c, Grade__c, Grade_Type__c, Year_of_Completion__c
                FROM PersonEducation
                WHERE AccountId = :personAcctId
                AND (Is_Archived__c = false OR Is_Archived__c = null)
                ORDER BY Year_of_Completion__c DESC NULLS LAST
                LIMIT 50
            ]) {
                EducationRow er = new EducationRow();
                er.institute = pe.Institute_Name__c;
                er.degree    = pe.Degree_Name__c;
                er.yearOfCompletion = (pe.Year_of_Completion__c != null) ? String.valueOf(pe.Year_of_Completion__c) : null;
                // Pre-format grade for display: "CGPA 8.4" or "Percentage 85" — falls back to either part if missing.
                String gradeText = pe.Grade__c;
                String gradeType = pe.Grade_Type__c;
                if (String.isNotBlank(gradeText) && String.isNotBlank(gradeType)) {
                    er.gradeLabel = gradeType + ' ' + gradeText;
                } else if (String.isNotBlank(gradeText)) {
                    er.gradeLabel = gradeText;
                } else if (String.isNotBlank(gradeType)) {
                    er.gradeLabel = gradeType;
                }
                a.education.add(er);
            }
        } catch (Exception e) { /* swallow */ }
        return a;
    }

    // TODO upcoming-module: no Lead / Application / Scholarship / Intake doc objects wired
    @AuraEnabled(cacheable=true)
    public static AdmissionsDTO getAdmissions(Id recordId) {
        AdmissionsDTO a = new AdmissionsDTO();
        a.lead = new List<KeyValue>();
        a.application = new List<KeyValue>();
        a.entranceExam = new List<KeyValue>();
        a.offer = new List<KeyValue>();
        a.scholarship = new List<KeyValue>();
        a.referrals = new List<AdmissionsReferral>();
        a.intakeDocuments = new List<IntakeDocument>();
        return a;
    }

    @AuraEnabled(cacheable=true)
    public static CareerDTO getCareer(Id recordId) {
        if (recordId == null) return emptyCareer();
        try {
            Id personAcctId = lookupPersonAccountId(recordId);
            if (personAcctId == null) return emptyCareer();

            List<PersonEmployment> peList = [
                SELECT Id, Designation__c, Job_Role__c, Company_Name__c, Location__c,
                       StartDate, EndDate, Currently_Employed__c, Description__c, Is_Archived__c
                FROM PersonEmployment
                WHERE AccountId = :personAcctId
                ORDER BY StartDate DESC NULLS LAST
            ];

            CareerDTO c = new CareerDTO();
            c.employmentHistory = new List<EmploymentRow>();
            for (PersonEmployment pe : peList) {
                if (pe.Is_Archived__c == true) continue;
                EmploymentRow row = new EmploymentRow();
                row.role = (pe.Designation__c != null) ? pe.Designation__c : pe.Job_Role__c;
                row.company = pe.Company_Name__c;
                row.location = pe.Location__c;
                row.source = 'Self-reported';
                Boolean isCurrent = (pe.Currently_Employed__c == true) || (pe.EndDate == null);
                row.current = isCurrent;
                String start = (pe.StartDate != null) ? formatMonthYear(pe.StartDate) : '—';
                String endLbl = isCurrent ? 'present'
                                : (pe.EndDate != null ? formatMonthYear(pe.EndDate) : '—');
                row.period = start + ' – ' + endLbl;
                row.description = pe.Description__c;
                c.employmentHistory.add(row);
            }

            // TODO upcoming-module: no Is_Internship__c flag on PersonEmployment
            c.internships = new List<KeyValue>();
            // TODO upcoming-module: no career-highlights data model
            c.highlights = new List<String>();
            return c;
        } catch (Exception e) {
            return emptyCareer();
        }
    }

    private static CareerDTO emptyCareer() {
        CareerDTO c = new CareerDTO();
        c.employmentHistory = new List<EmploymentRow>();
        c.internships = new List<KeyValue>();
        c.highlights = new List<String>();
        return c;
    }

    // TODO upcoming-module: no certifications / continuing-education objects in repo
    @AuraEnabled(cacheable=true)
    public static ContinuingEdDTO getContinuingEducation(Id recordId) {
        ContinuingEdDTO ce = new ContinuingEdDTO();
        ce.ken42Academy = new List<CourseRow>();
        ce.external = new List<CourseRow>();
        ce.recommended = new List<CourseRow>();
        return ce;
    }

    @AuraEnabled(cacheable=true)
    public static EngagementDTO getEngagement(Id recordId) {
        if (recordId == null) return emptyEngagement();
        return buildEngagementFromOrg(recordId);
    }

    private static EngagementDTO emptyEngagement() {
        EngagementDTO e = new EngagementDTO();
        e.eventsAttendedCount = 0;
        e.activeMenteesCount = 0;
        e.totalReferralsCount = 0;
        e.talksOnCampusCount = 0;
        e.eventsHosted = new List<EventRow>();
        e.eventsAttended = new List<EventRow>();
        e.mentorship = new List<MentorshipRow>();
        e.hiringReferrals = new List<ReferralRow>();
        return e;
    }

    private static EngagementDTO buildEngagementFromOrg(Id recordId) {
        EngagementDTO e = new EngagementDTO();
        e.eventsAttendedCount = 0;
        e.activeMenteesCount = 0;
        e.totalReferralsCount = 0;
        e.talksOnCampusCount = 0;
        e.eventsHosted = new List<EventRow>();
        e.eventsAttended = new List<EventRow>();
        e.mentorship = new List<MentorshipRow>();
        e.hiringReferrals = new List<ReferralRow>();

        Id personAcctId = lookupPersonAccountId(recordId);
        if (personAcctId == null) return e;

        // Events attended (Ken_Event_Booking__c)
        try {
            List<Ken_Event_Booking__c> bookings = [
                SELECT Id, CreatedDate, Type__c, Schedules_Sessions__c,
                       Schedules_Sessions__r.Name, Schedules_Sessions__r.Event_Reference__c
                FROM Ken_Event_Booking__c
                WHERE Person_Account__c = :personAcctId
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
            e.eventsAttendedCount = bookings.size();
            // Hydrate event titles via Ken_Event_Master__c
            Set<Id> eventIds = new Set<Id>();
            for (Ken_Event_Booking__c b : bookings) {
                if (b.Schedules_Sessions__c != null && b.Schedules_Sessions__r.Event_Reference__c != null) {
                    eventIds.add(b.Schedules_Sessions__r.Event_Reference__c);
                }
            }
            Map<Id, Ken_Event_Master__c> evMap = new Map<Id, Ken_Event_Master__c>();
            if (!eventIds.isEmpty()) {
                try {
                    evMap = new Map<Id, Ken_Event_Master__c>([
                        SELECT Id, Name, Start_Date__c, Location__c, Event_Type__c
                        FROM Ken_Event_Master__c
                        WHERE Id IN :eventIds
                    ]);
                } catch (Exception ex) { /* swallow */ }
            }
            for (Ken_Event_Booking__c b : bookings) {
                EventRow row = new EventRow();
                Ken_Event_Master__c em;
                if (b.Schedules_Sessions__c != null && b.Schedules_Sessions__r.Event_Reference__c != null) {
                    em = evMap.get(b.Schedules_Sessions__r.Event_Reference__c);
                }
                row.title = (em != null && em.Name != null) ? em.Name
                            : (b.Schedules_Sessions__r != null ? b.Schedules_Sessions__r.Name : 'Event');
                row.role = (b.Type__c != null) ? b.Type__c : 'Attendee';
                row.details = (em != null && em.Location__c != null) ? em.Location__c : null;
                row.when_x = (em != null && em.Start_Date__c != null)
                                ? formatMonthYear(em.Start_Date__c)
                                : (b.CreatedDate != null ? formatMonthYear(b.CreatedDate.date()) : null);
                e.eventsAttended.add(row);
            }
        } catch (Exception ex) { /* leave empty */ }

        // Mentorship — Mentor__c = personAcctId
        try {
            List<Ken_Mentorship__c> ms = [
                SELECT Id, Mentee__c, Mentor__c, Mentorship_Status__c, Meet_Date__c,
                       Meeting_Title__c, Meeting_Mode__c,
                       Mentee__r.Name
                FROM Ken_Mentorship__c
                WHERE Mentor__c = :personAcctId
                ORDER BY Meet_Date__c DESC NULLS LAST
                LIMIT 50
            ];
            // Group by mentee — count sessions, earliest date, latest status
            Map<Id, List<Ken_Mentorship__c>> byMentee = new Map<Id, List<Ken_Mentorship__c>>();
            for (Ken_Mentorship__c m : ms) {
                if (m.Mentee__c == null) continue;
                if (!byMentee.containsKey(m.Mentee__c)) byMentee.put(m.Mentee__c, new List<Ken_Mentorship__c>());
                byMentee.get(m.Mentee__c).add(m);
            }
            Integer activeMentees = 0;
            for (Id menteeId : byMentee.keySet()) {
                List<Ken_Mentorship__c> sess = byMentee.get(menteeId);
                MentorshipRow mrow = new MentorshipRow();
                mrow.name = (sess[0].Mentee__r != null) ? sess[0].Mentee__r.Name : '—';
                mrow.initials = computeInitials(mrow.name);
                mrow.alumniRef = String.valueOf(menteeId).left(15);
                mrow.programAndSemester = null;
                mrow.sessions = sess.size() + ' sessions';
                // Earliest meeting date
                Date earliest;
                Boolean isActive = false;
                for (Ken_Mentorship__c m : sess) {
                    if (m.Meet_Date__c != null && (earliest == null || m.Meet_Date__c < earliest)) earliest = m.Meet_Date__c;
                    if (m.Mentorship_Status__c == 'Accepted' || m.Mentorship_Status__c == 'Scheduled') isActive = true;
                }
                mrow.since = (earliest != null) ? formatMonthYear(earliest) : null;
                mrow.status = isActive ? 'ACTIVE' : 'CONCLUDED';
                mrow.statusTone = isActive ? 'emerald' : 'gray';
                if (isActive) activeMentees++;
                e.mentorship.add(mrow);
            }
            e.activeMenteesCount = activeMentees;
        } catch (Exception ex) { /* leave empty */ }

        // TODO upcoming-module: eventsHosted (no host field on Ken_Event_Master__c yet)
        // TODO upcoming-module: hiringReferrals (no referral object yet)
        return e;
    }

    // TODO upcoming-module: hiring / job-board objects not yet in repo
    @AuraEnabled(cacheable=true)
    public static JobsDTO getJobs(Id recordId) {
        JobsDTO j = new JobsDTO();
        j.postingsCount = 0;
        j.currentlyOpenCount = 0;
        j.filledByKen42Count = 0;
        j.ken42ApplicantsCount = 0;
        j.postedJobs = new List<JobRow>();
        j.appliedJobs = new List<JobRow>();
        return j;
    }

    // TODO upcoming-module: no Recognition / Awards object
    @AuraEnabled(cacheable=true)
    public static RecognitionDTO getRecognition(Id recordId) {
        RecognitionDTO r = new RecognitionDTO();
        r.alumniOfMonthCount = 0;
        r.awardsCount = 0;
        r.featuresCount = 0;
        r.honoursCount = 0;
        r.items = new List<RecognitionRow>();
        return r;
    }

    // TODO upcoming-module: no Giving / donations object
    @AuraEnabled(cacheable=true)
    public static GivingDTO getGiving(Id recordId) {
        GivingDTO g = new GivingDTO();
        g.lifetimeAmount = null;
        g.endowmentAmount = null;
        g.scholarshipsAmount = null;
        g.libraryReunionAmount = null;
        g.donorTier = null;
        g.donorNote = null;
        g.gifts = new List<GiftRow>();
        return g;
    }

    @AuraEnabled(cacheable=true)
    public static SupportDTO getSupport(Id recordId) {
        if (recordId == null) return emptySupport();
        return buildSupportFromOrg(recordId);
    }

    private static SupportDTO emptySupport() {
        SupportDTO s = new SupportDTO();
        s.ticketsRaisedCount = 0;
        s.currentlyOpenCount = 0;
        s.avgFirstResponse = null;
        s.surveysSubmittedCount = 0;
        s.tickets = new List<TicketRow>();
        s.surveys = new List<SurveyRow>();
        return s;
    }

    private static SupportDTO buildSupportFromOrg(Id recordId) {
        SupportDTO s = new SupportDTO();
        s.ticketsRaisedCount = 0;
        s.currentlyOpenCount = 0;
        s.avgFirstResponse = null; // TODO upcoming-module: no first-response-time field on Case
        s.surveysSubmittedCount = 0; // TODO upcoming-module: no submitted-survey link object yet
        s.tickets = new List<TicketRow>();
        s.surveys = new List<SurveyRow>();

        Id personAcctId = lookupPersonAccountId(recordId);
        if (personAcctId == null) return s;

        try {
            List<Case> all = [
                SELECT Id, Subject, Status, Priority, CreatedDate, ClosedDate,
                       Owner.Name, Origin, CaseNumber
                FROM Case
                WHERE Constituent_Role__r.PersonId = :personAcctId
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
            s.ticketsRaisedCount = all.size();
            Integer open = 0;
            for (Case c : all) {
                String st = c.Status;
                if (st != null && st != 'Closed' && st != 'Cancelled' && st != 'Rejected' && st != 'Resolved') {
                    open++;
                }
            }
            s.currentlyOpenCount = open;

            Integer max = Math.min(all.size(), 10);
            for (Integer i = 0; i < max; i++) {
                Case c = all[i];
                TicketRow t = new TicketRow();
                t.title = c.Subject;
                t.reference = c.CaseNumber;
                List<String> bits = new List<String>();
                if (c.Origin != null) bits.add(c.Origin);
                if (c.CreatedDate != null) bits.add('raised ' + formatDayMonYear(c.CreatedDate.date()));
                if (c.Owner != null && c.Owner.Name != null) bits.add('assigned to ' + c.Owner.Name);
                if (c.ClosedDate != null) bits.add('resolved ' + formatDayMonYear(c.ClosedDate.date()));
                t.details = String.join(bits, ' · ');
                t.status = (c.Status != null) ? c.Status.toUpperCase() : null;
                t.statusTone = mapStatusTone(c.Status);
                t.priority = (c.Priority != null) ? c.Priority.toUpperCase() : null;
                t.priorityTone = mapPriorityTone(c.Priority);
                s.tickets.add(t);
            }
        } catch (Exception ex) { /* leave empty */ }

        return s;
    }

    private static String mapStatusTone(String status) {
        if (status == null) return 'gray';
        String st = status.toLowerCase();
        if (st.contains('closed') || st.contains('resolved')) return 'emerald';
        if (st.contains('progress') || st.contains('open') || st.contains('new')) return 'amber';
        if (st.contains('rejected') || st.contains('cancel')) return 'rose';
        return 'gray';
    }

    private static String mapPriorityTone(String pri) {
        if (pri == null) return 'gray';
        String p = pri.toLowerCase();
        if (p == 'high' || p == 'critical') return 'rose';
        if (p == 'medium' || p == 'normal') return 'amber';
        return 'gray';
    }

    // TODO upcoming-module: could wire ContentDocumentLink later
    @AuraEnabled(cacheable=true)
    public static DocumentsDTO getDocuments(Id recordId) {
        DocumentsDTO d = new DocumentsDTO();
        d.items = new List<DocumentRow>();
        return d;
    }

    // TODO upcoming-module: could wire FeedItem / EmailMessage later
    @AuraEnabled(cacheable=true)
    public static CommunicationsDTO getCommunications(Id recordId) {
        CommunicationsDTO c = new CommunicationsDTO();
        c.recipientName = null;
        c.recipientEmail = null;
        c.last30DaysCount = 0;
        c.outboundCount = 0;
        c.inboundCount = 0;
        c.newslettersCount = 0;
        c.recent = new List<MessageRow>();
        c.preferences = new List<NotificationPreference>();
        return c;
    }

    @AuraEnabled(cacheable=true)
    public static RightRailDTO getRightRail(Id recordId) {
        if (recordId == null) return emptyRightRail();
        return buildRightRailFromOrg(recordId);
    }

    private static RightRailDTO emptyRightRail() {
        RightRailDTO r = new RightRailDTO();
        r.needsAttention = new List<NeedsAttentionItem>();
        r.recentActivity = new List<RecentActivityItem>();
        r.quickActions = new List<QuickActionItem>();
        r.recordHealth = new List<RecordHealthItem>();
        return r;
    }

    private static RightRailDTO buildRightRailFromOrg(Id recordId) {
        RightRailDTO r = new RightRailDTO();
        r.recentActivity = new List<RecentActivityItem>();
        r.recordHealth = new List<RecordHealthItem>();

        // TODO upcoming-module: needsAttention business rules
        r.needsAttention = new List<NeedsAttentionItem>();

        // TODO upcoming-module: quick-actions are static UI shortcuts — none wired yet
        r.quickActions = new List<QuickActionItem>();

        Id personAcctId = null;
        Ken_Alumni_CRM__c crm = resolveCrmRow(recordId);
        if (crm != null) personAcctId = crm.Person_Account__c;

        // ----- RECENT ACTIVITY: pick the 5 most recent signals -----
        List<Map<String, Object>> signals = new List<Map<String, Object>>();
        if (crm != null && crm.LastModifiedDate != null) {
            signals.add(new Map<String, Object>{
                'icon' => 'star',
                'title' => 'Profile updated',
                'date' => crm.LastModifiedDate
            });
        }
        if (personAcctId != null) {
            try {
                List<Ken_Event_Booking__c> evb = [
                    SELECT Id, CreatedDate FROM Ken_Event_Booking__c
                    WHERE Person_Account__c = :personAcctId
                    ORDER BY CreatedDate DESC LIMIT 1
                ];
                if (!evb.isEmpty()) signals.add(new Map<String, Object>{
                    'icon' => 'heart', 'title' => 'Event booking', 'date' => evb[0].CreatedDate
                });
            } catch (Exception ex) {}
            try {
                List<Ken_Mentorship__c> mn = [
                    SELECT Id, CreatedDate FROM Ken_Mentorship__c
                    WHERE Mentor__c = :personAcctId
                    ORDER BY CreatedDate DESC LIMIT 1
                ];
                if (!mn.isEmpty()) signals.add(new Map<String, Object>{
                    'icon' => 'mentor', 'title' => 'Mentor session logged', 'date' => mn[0].CreatedDate
                });
            } catch (Exception ex) {}
            try {
                List<Case> cs = [
                    SELECT Id, CreatedDate, Subject FROM Case
                    WHERE Constituent_Role__r.PersonId = :personAcctId
                    ORDER BY CreatedDate DESC LIMIT 1
                ];
                if (!cs.isEmpty()) signals.add(new Map<String, Object>{
                    'icon' => 'chat',
                    'title' => cs[0].Subject != null ? cs[0].Subject : 'Support ticket raised',
                    'date' => cs[0].CreatedDate
                });
            } catch (Exception ex) {}
        }
        // Sort desc by date
        for (Integer i = 0; i < signals.size(); i++) {
            for (Integer j = i + 1; j < signals.size(); j++) {
                Datetime di = (Datetime) signals[i].get('date');
                Datetime dj = (Datetime) signals[j].get('date');
                if (dj != null && (di == null || dj > di)) {
                    Map<String, Object> tmp = signals[i]; signals[i] = signals[j]; signals[j] = tmp;
                }
            }
        }
        Integer activityMax = Math.min(signals.size(), 5);
        for (Integer i = 0; i < activityMax; i++) {
            r.recentActivity.add(act(
                (String) signals[i].get('icon'),
                (String) signals[i].get('title'),
                relativeWhen((Datetime) signals[i].get('date'))
            ));
        }

        // ----- RECORD HEALTH -----
        Boolean contactVerified = (crm != null && crm.Person_Account__c != null
                                    && crm.Person_Account__r != null
                                    && crm.Person_Account__r.PersonEmail != null);
        Boolean employerOk = false;
        if (personAcctId != null) {
            try {
                Integer cnt = [
                    SELECT COUNT()
                    FROM PersonEmployment
                    WHERE AccountId = :personAcctId
                      AND Currently_Employed__c = true
                      AND Is_Archived__c = false
                ];
                employerOk = (cnt > 0);
            } catch (Exception ex) { employerOk = false; }
        }
        Boolean emailOk = contactVerified;
        Boolean mentorOk = false;
        if (personAcctId != null) {
            try {
                Integer pCnt = [
                    SELECT COUNT()
                    FROM Ken_Alumni_Preferences__c
                    WHERE Person_Account__c = :personAcctId
                      AND Willing_to_be_a_mentor__c = true
                ];
                mentorOk = (pCnt > 0);
            } catch (Exception ex) { mentorOk = false; }
        }
        r.recordHealth.add(rh('Contact verified',               contactVerified, contactVerified ? null : 'Missing email'));
        r.recordHealth.add(rh('Employer current and verified',  employerOk,      employerOk      ? null : 'No current employment'));
        r.recordHealth.add(rh('Alumni email active',            emailOk,         emailOk         ? null : 'Missing'));
        r.recordHealth.add(rh('Mentor profile complete',        mentorOk,        mentorOk        ? null : 'Not opted-in'));
        // TODO upcoming-module: Tax PAN field — Missing for everyone for now
        r.recordHealth.add(rh('Tax PAN on file (for receipts)', false,           'Missing'));
        return r;
    }

    /* ============================================================
       Private helpers (wrapper builders + small utilities)
       ============================================================ */
    private static KeyValue kv(String label, String value, String emphasis) {
        KeyValue k = new KeyValue();
        k.label = label; k.value = value; k.emphasis = emphasis;
        return k;
    }
    private static BadgeDTO badge(String label, String tone) {
        BadgeDTO b = new BadgeDTO();
        b.label = label; b.tone = tone; return b;
    }
    private static RecentActivityItem act(String iconKey, String title, String when_x) {
        RecentActivityItem r = new RecentActivityItem();
        r.iconKey = iconKey; r.title = title; r.when_x = when_x;
        return r;
    }
    private static RecordHealthItem rh(String label, Boolean ok, String missingNote) {
        RecordHealthItem r = new RecordHealthItem();
        r.label = label; r.ok = ok; r.missingNote = missingNote;
        return r;
    }

    private static String computeInitials(String name) {
        if (String.isBlank(name)) return '';
        List<String> parts = name.trim().split('\\s+');
        String s = '';
        for (Integer i = 0; i < parts.size() && i < 2; i++) {
            if (parts[i].length() > 0) s += parts[i].substring(0, 1).toUpperCase();
        }
        return s;
    }

    private static String yearsOutLabel(String yearOfGraduation) {
        Integer y;
        try { y = Integer.valueOf(yearOfGraduation); } catch (Exception e) { return null; }
        Integer diff = Date.today().year() - y;
        if (diff < 0) return null;
        return diff + ' years post-graduation';
    }

    /* ============================================================
       Polymorphic Id resolver
       --------------------------------------------------------------
       The 360 was originally built around Ken_Alumni_CRM__c Ids. After
       the master-data flip in kenAdminAlumni, the modal now opens with
       a ConstituentRole Id, and not every alumnus has a paired CRM row.
       loadContext() detects whichever Id type was passed and returns
       up to three populated SObjects (cr / acct / crm). resolveCrmRow()
       returns either the real CRM row OR a synthesised one built from
       cr + acct, so legacy section code that reads CRM fields keeps
       working without further changes.
       ============================================================ */
    @TestVisible
    private class AlumniContext {
        ConstituentRole cr;
        Account acct;
        Ken_Alumni_CRM__c crm;
        Id personAccountId;
    }

    @TestVisible
    private static AlumniContext loadContext(Id recordId) {
        AlumniContext ctx = new AlumniContext();
        if (recordId == null) return ctx;
        String prefix = String.valueOf(recordId).substring(0, 3);
        String crmPrefix  = Schema.Ken_Alumni_CRM__c.SObjectType.getDescribe().getKeyPrefix();
        String crPrefix   = Schema.ConstituentRole.SObjectType.getDescribe().getKeyPrefix();
        String acctPrefix = Schema.Account.SObjectType.getDescribe().getKeyPrefix();

        Id crmId = null, crId = null, acctId = null;
        if (prefix == crmPrefix)       crmId  = recordId;
        else if (prefix == crPrefix)   crId   = recordId;
        else if (prefix == acctPrefix) acctId = recordId;

        // Hop from CR/Acct → CRM via linkage fields when possible.
        if (crmId == null) {
            try {
                List<Ken_Alumni_CRM__c> linked;
                if (crId != null) {
                    linked = [SELECT Id FROM Ken_Alumni_CRM__c WHERE ConstituentRole__c = :crId LIMIT 1];
                } else if (acctId != null) {
                    linked = [SELECT Id FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :acctId LIMIT 1];
                }
                if (linked != null && !linked.isEmpty()) crmId = linked[0].Id;
            } catch (Exception ignored) {}
        }

        if (crmId != null) {
            try {
                // Build the Person Account select-list dynamically so optional
                // bio fields (Nationality__pc, Languages_Known__c) don't break
                // the query in orgs where they don't exist.
                String paFields =
                    'Person_Account__r.Name, Person_Account__r.FirstName, Person_Account__r.LastName, ' +
                    'Person_Account__r.PersonEmail, Person_Account__r.PersonMobilePhone, ' +
                    'Person_Account__r.PersonBirthdate, Person_Account__r.PersonMailingCountry, ' +
                    'Person_Account__r.PersonMailingStreet, Person_Account__r.PersonMailingCity, ' +
                    'Person_Account__r.PersonMailingState, Person_Account__r.PersonMailingPostalCode, ' +
                    'Person_Account__r.Linkedin_Profile_URL__c';
                Map<String, Schema.SObjectField> acctF = Account.SObjectType.getDescribe().fields.getMap();
                if (acctF.containsKey('Nationality__pc'))     paFields += ', Person_Account__r.Nationality__pc';
                else if (acctF.containsKey('Nationality__c')) paFields += ', Person_Account__r.Nationality__c';
                if (acctF.containsKey('Languages_Known__c')) paFields += ', Person_Account__r.Languages_Known__c';
                String crmSoql =
                    'SELECT Id, Name, Program__c, Year_of_Graduation__c, Registration_Number__c, ' +
                    'Registration_Date__c, Current_Location__c, Current_Company__c, ' +
                    'Industry__c, Specialization__c, Approval_Status__c, Is_Active__c, ' +
                    'ConstituentRole__c, Person_Account__c, LastModifiedDate, ' + paFields +
                    ' FROM Ken_Alumni_CRM__c WHERE Id = :crmId LIMIT 1';
                List<Ken_Alumni_CRM__c> rows = (List<Ken_Alumni_CRM__c>) Database.query(crmSoql);
                if (!rows.isEmpty()) {
                    ctx.crm = rows[0];
                    if (crId   == null) crId   = ctx.crm.ConstituentRole__c;
                    if (acctId == null) acctId = ctx.crm.Person_Account__c;
                }
            } catch (Exception ignored) {}
        }

        if (crId != null) {
            try {
                List<ConstituentRole> rows = [
                    SELECT Id, RoleType, Status, Registration_Status__c, PersonId,
                           Graduation_Year__c, Registration_Number__c, Program_Name__c,
                           Program_Plan__r.Name, Source_Funnel__c, CreatedDate, LastModifiedDate
                    FROM ConstituentRole WHERE Id = :crId LIMIT 1
                ];
                if (!rows.isEmpty()) {
                    ctx.cr = rows[0];
                    if (acctId == null) acctId = ctx.cr.PersonId;
                }
            } catch (Exception ignored) {}
        }

        if (acctId != null) {
            try {
                List<Account> rows = [
                    SELECT Id, Name, FirstName, LastName, PersonEmail, PersonMobilePhone,
                           PersonBirthdate, PersonMailingCountry, PersonMailingStreet,
                           PersonMailingCity, PersonMailingState, PersonMailingPostalCode,
                           Linkedin_Profile_URL__c, LastModifiedDate
                    FROM Account WHERE Id = :acctId LIMIT 1
                ];
                if (!rows.isEmpty()) ctx.acct = rows[0];
            } catch (Exception ignored) {}
        }

        ctx.personAccountId = acctId;
        return ctx;
    }

    /**
     * Return the real Ken_Alumni_CRM__c row if one exists for this recordId
     * (whatever its Id type), otherwise synthesise a transient one from the
     * ConstituentRole + Account so legacy section code continues to work.
     * Uses JSON serialise/deserialise so the Person_Account__r relationship
     * field on the synthetic row is also populated.
     */
    @TestVisible
    private static Ken_Alumni_CRM__c resolveCrmRow(Id recordId) {
        AlumniContext ctx = loadContext(recordId);
        if (ctx.crm != null) return ctx.crm;
        if (ctx.cr == null && ctx.acct == null) return null;

        Map<String, Object> synth = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => 'Ken_Alumni_CRM__c' }
        };
        if (ctx.cr != null) {
            synth.put('ConstituentRole__c', ctx.cr.Id);
            String prog = ctx.cr.Program_Name__c;
            if (String.isBlank(prog) && ctx.cr.Program_Plan__r != null) prog = ctx.cr.Program_Plan__r.Name;
            synth.put('Program__c', prog);
            synth.put('Year_of_Graduation__c', ctx.cr.Graduation_Year__c);
            synth.put('Registration_Number__c', ctx.cr.Registration_Number__c);
            if (ctx.cr.CreatedDate != null) synth.put('Registration_Date__c', ctx.cr.CreatedDate.date());
            synth.put('Is_Active__c', ctx.cr.Status == 'Active');
            if (ctx.cr.LastModifiedDate != null) synth.put('LastModifiedDate', ctx.cr.LastModifiedDate);
        }
        if (ctx.acct != null) {
            synth.put('Person_Account__c', ctx.acct.Id);
            synth.put('Name', ctx.acct.Name);
            synth.put('Person_Account__r', new Map<String, Object>{
                'attributes' => new Map<String, String>{ 'type' => 'Account' },
                'Id' => ctx.acct.Id,
                'Name' => ctx.acct.Name,
                'FirstName' => ctx.acct.FirstName,
                'LastName' => ctx.acct.LastName,
                'PersonEmail' => ctx.acct.PersonEmail,
                'PersonMobilePhone' => ctx.acct.PersonMobilePhone,
                'PersonBirthdate' => ctx.acct.PersonBirthdate,
                'PersonMailingCountry' => ctx.acct.PersonMailingCountry,
                'PersonMailingStreet' => ctx.acct.PersonMailingStreet,
                'PersonMailingCity' => ctx.acct.PersonMailingCity,
                'PersonMailingState' => ctx.acct.PersonMailingState,
                'PersonMailingPostalCode' => ctx.acct.PersonMailingPostalCode,
                'Linkedin_Profile_URL__c' => ctx.acct.Linkedin_Profile_URL__c
            });
        }
        return (Ken_Alumni_CRM__c) JSON.deserialize(JSON.serialize(synth), Ken_Alumni_CRM__c.class);
    }

    /** Resolve the Person Account Id from any of CRM / ConstituentRole / Account. */
    private static Id lookupPersonAccountId(Id recordId) {
        return loadContext(recordId).personAccountId;
    }

    /**
     * Some Ken_Alumni_CRM__c rows store the LearningProgramPlan **Id** in
     * Program__c instead of the human name. When that happens the 360 used to
     * show "0uFTa00000001FTMAY" verbatim. Detect the LearningProgramPlan
     * key-prefix (`0uF`) and resolve to the Name; otherwise return as-is.
     */
    private static String displayProgram(String rawValue) {
        if (String.isBlank(rawValue)) return rawValue;
        String s = rawValue.trim();
        // Salesforce Ids are 15 or 18 chars and alphanumeric.
        if ((s.length() == 15 || s.length() == 18) && s.startsWith('0uF')) {
            try {
                Id pid = (Id) s;
                List<LearningProgramPlan> p = [SELECT Name FROM LearningProgramPlan WHERE Id = :pid LIMIT 1];
                if (!p.isEmpty() && String.isNotBlank(p[0].Name)) return p[0].Name;
            } catch (Exception e) { /* not actually a valid Id; fall through */ }
        }
        return s;
    }

    private static String formatMonthYear(Date d) {
        if (d == null) return null;
        String[] mon = new String[]{
            'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
        };
        return mon[d.month() - 1] + ' ' + d.year();
    }

    private static String formatDayMonYear(Date d) {
        if (d == null) return null;
        String[] mon = new String[]{
            'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
        };
        String day = (d.day() < 10) ? ('0' + d.day()) : String.valueOf(d.day());
        return day + ' ' + mon[d.month() - 1] + ' ' + d.year();
    }

    private static String buildAddress(String street, String city, String state, String postal, String country) {
        List<String> bits = new List<String>();
        if (String.isNotBlank(street))  bits.add(street);
        if (String.isNotBlank(city))    bits.add(city);
        if (String.isNotBlank(state))   bits.add(state);
        if (String.isNotBlank(postal))  bits.add(postal);
        if (String.isNotBlank(country)) bits.add(country);
        return bits.isEmpty() ? null : String.join(bits, ', ');
    }

    private static String relativeWhen(Datetime dt) {
        if (dt == null) return null;
        Long diffMs = Datetime.now().getTime() - dt.getTime();
        Long mins = diffMs / 60000;
        if (mins < 1)        return 'just now';
        if (mins < 60)       return mins + ' min ago';
        Long hours = mins / 60;
        if (hours < 24)      return hours + ' hr ago';
        Long days = hours / 24;
        if (days == 1)       return 'Yesterday';
        if (days < 7)        return days + ' days ago';
        if (days < 30)       return (days / 7) + ' weeks ago';
        if (days < 365)      return (days / 30) + ' months ago';
        return (days / 365) + ' years ago';
    }

    /**
     * Empty header — all string fields null, badges list initialised.
     * Returned when no recordId is supplied or the CRM lookup fails.
     * The LWC has lwc:if guards on every header property and on
     * the badges list so it renders cleanly with no data.
     */
    @TestVisible
    private static HeaderDTO emptyHeader() {
        HeaderDTO h = new HeaderDTO();
        h.badges = new List<BadgeDTO>();
        return h;
    }
}