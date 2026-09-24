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
 *   - getHeader(recordId) reads the ConstituentRole (the same master object
 *     used by KenAdminAlumniController) and its Person Account for
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
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String role;               // ALUMNA / ALUMNUS
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String classOf;
        @AuraEnabled public String program;
        @AuraEnabled public String programDates;
        @AuraEnabled public String yearsOut;
        @AuraEnabled public String school;
        @AuraEnabled public String campus;
        @AuraEnabled public String status;
        @AuraEnabled public String legacyId;
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
        @AuraEnabled public String program;
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
       smallest possible set of records — Person Account, ConstituentRole,
       PersonEmployment and the Mailing address. Nothing is written when a
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
     * Fallback dropdown options for Blood_Group__c, used only in orgs where the
     * field is still Text and picklist describe returns nothing. Orgs matching
     * KJS production have it as a Picklist and supply their own values.
     */
    private static final List<String> BLOOD_GROUP_VALUES = new List<String>{
        'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
    };

    /**
     * Person Account bio fields read dynamically because they don't exist
     * (or aren't enabled) in every client org.
     */
    private static final List<String> SYNTH_BIO_FIELDS = new List<String>{
        'PersonGenderIdentity', 'Nationality__pc', 'Nationality__c', 'Languages_Known__c', 'Blood_Group__c'
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
                    KenNamespaceUtil.resolveFieldMap(objectApiName)
                        .get(fieldApiName).getDescribe();
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
            String natField  = KenNamespaceUtil.hasField(af, 'Nationality__c') ? 'Nationality__c'
                              : (af.containsKey('Nationality__pc') ? 'Nationality__pc' : null);
            String langField = KenNamespaceUtil.hasField(af, 'Languages_Known__c') ? 'Languages_Known__c' : null;
            List<String> fields = new List<String>{
                'PersonEmail','PersonMobilePhone','Linkedin_Profile_URL__c','Twitter_Profile_URL__c','PersonBirthdate',
                'PersonMailingStreet','PersonMailingCity','PersonMailingState',
                'PersonMailingPostalCode','PersonMailingCountry','PersonGenderIdentity'
            };
            if (natField  != null) fields.add(natField);
            if (langField != null) fields.add(langField);
            if (KenNamespaceUtil.hasField(af, 'Blood_Group__c')) fields.add('Blood_Group__c');
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
                    m.put('twitter',     a.Twitter_Profile_URL__c);
                    m.put('dob',         a.PersonBirthdate);                 // serialises as yyyy-MM-dd
                    m.put('street',      a.PersonMailingStreet);
                    m.put('city',        a.PersonMailingCity);
                    m.put('state',       a.PersonMailingState);
                    m.put('postalCode',  a.PersonMailingPostalCode);
                    m.put('country',     a.PersonMailingCountry);
                    m.put('nationality', natField  != null ? a.get(natField)  : null);
                    m.put('languages',   langField != null ? a.get(langField) : null);
                    m.put('gender',      a.get('PersonGenderIdentity'));
                    m.put('bloodGroup',  KenNamespaceUtil.hasField(af, 'Blood_Group__c') ? a.get(KenNamespaceUtil.qualifyCustom('Blood_Group__c')) : null);
                    if (String.isBlank(a.PersonMailingCity) && String.isBlank(a.PersonMailingState)
                        && String.isBlank(a.PersonMailingCountry)) {
                        List<Ken_Address__c> ka = [
                            SELECT Street__c, City__c, State__c, Pincode__c, Country__c
                            FROM Ken_Address__c
                            WHERE Person_Account__c = :pid
                              AND Address_Type__c = 'Mailing'
                            WITH USER_MODE
                            LIMIT 1
                        ];
                        if (!ka.isEmpty()) {
                            m.put('street',     ka[0].Street__c);
                            m.put('city',       ka[0].City__c);
                            m.put('state',      ka[0].State__c);
                            m.put('postalCode', ka[0].Pincode__c);
                            m.put('country',    ka[0].Country__c);
                        }
                    }
                }
            } catch (Exception ignored) { /* leave account fields out */ }
            // Nationality picklist options (empty when the org still has it as a
            // plain text field — the LWC then falls back to a text input).
            m.put('nationalityOptions', picklistOptions('Account', natField, NATIONALITY_VALUES));
            m.put('genderOptions', picklistOptions('Account', 'PersonGenderIdentity', new List<String>()));
            m.put('bloodGroupOptions', picklistOptions('Account', KenNamespaceUtil.hasField(af, 'Blood_Group__c') ? 'Blood_Group__c' : null,
                KenNamespaceUtil.hasField(af, 'Blood_Group__c') ? BLOOD_GROUP_VALUES : new List<String>()));
        }

        // ----- Academic fields from the ConstituentRole; employment and
        // location resolved from their own objects -----
        if (ctx.cr != null && ctx.cr.Id != null) {
            m.put('crmEditable',        true);
            m.put('classOf',            ctx.cr.Graduation_Year__c);
            m.put('registrationNumber', ctx.cr.Registration_Number__c);
        }
        if (ctx.personAccountId != null) {
            try {
                KenAlumniProfileService.EmploymentSnapshot emp =
                    KenAlumniProfileService.currentEmployment(ctx.personAccountId);
                if (emp != null) {
                    m.put('currentCompany', emp.company);
                    m.put('industry',       emp.industry);
                }
                m.put('campus', KenAlumniProfileService.currentLocation(ctx.personAccountId));
            } catch (Exception ignored) { /* leave employment fields out */ }
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
        String natField  = KenNamespaceUtil.hasField(af, 'Nationality__c') ? 'Nationality__c'
                          : (af.containsKey('Nationality__pc') ? 'Nationality__pc' : null);
        String langField = KenNamespaceUtil.hasField(af, 'Languages_Known__c') ? 'Languages_Known__c' : null;

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
                else if (key == 'twitter')    { acct.Twitter_Profile_URL__c = s; acctDirty = true; }
                else if (key == 'dob')        { acct.PersonBirthdate = (s == null) ? null : Date.valueOf(s); acctDirty = true; }
                else if (key == 'street')     { acct.PersonMailingStreet = s; acctDirty = true; }
                else if (key == 'city')       { acct.PersonMailingCity = s; acctDirty = true; }
                else if (key == 'state')      { acct.PersonMailingState = s; acctDirty = true; }
                else if (key == 'postalCode') { acct.PersonMailingPostalCode = s; acctDirty = true; }
                else if (key == 'country')    { acct.PersonMailingCountry = s; acctDirty = true; }
                else if (key == 'nationality' && natField  != null) { acct.put(natField, s); acctDirty = true; }
                else if (key == 'languages'  && langField != null) { acct.put(langField, s); acctDirty = true; }
                else if (key == 'gender')     { acct.put('PersonGenderIdentity', s); acctDirty = true; }
                else if (key == 'bloodGroup' && KenNamespaceUtil.hasField(af, 'Blood_Group__c')) { acct.put(KenNamespaceUtil.qualifyCustom('Blood_Group__c'), s); acctDirty = true; }
            }
        }

        // ----- Academic edits land on the ConstituentRole -----
        ConstituentRole crUpd;
        Boolean crUpdDirty = false;
        if (ctx.cr != null && ctx.cr.Id != null) {
            crUpd = new ConstituentRole(Id = ctx.cr.Id);
            for (String key : changes.keySet()) {
                Object v = changes.get(key);
                String s = (v == null) ? null : String.valueOf(v);
                if (String.isBlank(s)) s = null;
                if (key == 'classOf')                 { crUpd.Graduation_Year__c = s; crUpdDirty = true; }
                else if (key == 'registrationNumber') { crUpd.Registration_Number__c = s; crUpdDirty = true; }
            }
        }

        // ----- Company and industry belong to the current employment row -----
        PersonEmployment empUpd;
        Boolean empDirty = false;
        if (ctx.personAccountId != null
            && (changes.containsKey('currentCompany') || changes.containsKey('industry'))) {
            String companyEdit = changes.get('currentCompany') == null
                ? null : blankToNull(String.valueOf(changes.get('currentCompany')));
            String industryEdit = changes.get('industry') == null
                ? null : blankToNull(String.valueOf(changes.get('industry')));
            List<PersonEmployment> currentEmp = [
                SELECT Id FROM PersonEmployment
                WHERE AccountId = :ctx.personAccountId
                  AND (Is_Archived__c = false OR Is_Archived__c = null)
                WITH USER_MODE
                ORDER BY Currently_Employed__c DESC, StartDate DESC NULLS LAST
                LIMIT 1
            ];
            if (!currentEmp.isEmpty()) {
                empUpd = new PersonEmployment(Id = currentEmp[0].Id);
                if (changes.containsKey('currentCompany')) { empUpd.Company_Name__c = companyEdit; empDirty = true; }
                if (changes.containsKey('industry'))       { empUpd.Industry__c = industryEdit; empDirty = true; }
            } else if (companyEdit != null || industryEdit != null) {
                empUpd = new PersonEmployment(
                    AccountId = ctx.personAccountId,
                    RelatedPersonId = ctx.personAccountId,
                    Name = companyEdit != null ? companyEdit.abbreviate(80) : 'Employment',
                    Company_Name__c = companyEdit,
                    Industry__c = industryEdit,
                    Currently_Employed__c = true,
                    Is_Archived__c = false
                );
                empDirty = true;
            }
        }

        // ----- Campus / location edits land on the Mailing address -----
        Ken_Address__c addrUpd;
        Boolean addrDirty = false;
        if (ctx.personAccountId != null && changes.containsKey('campus')) {
            String campusEdit = changes.get('campus') == null
                ? null : blankToNull(String.valueOf(changes.get('campus')));
            List<Ken_Address__c> mailing = [
                SELECT Id FROM Ken_Address__c
                WHERE Person_Account__c = :ctx.personAccountId AND Address_Type__c = 'Mailing'
                WITH USER_MODE
                LIMIT 1
            ];
            if (!mailing.isEmpty()) {
                addrUpd = new Ken_Address__c(Id = mailing[0].Id, City__c = campusEdit);
                addrDirty = true;
            } else if (campusEdit != null) {
                addrUpd = new Ken_Address__c(
                    Person_Account__c = ctx.personAccountId,
                    Address_Type__c = 'Mailing',
                    City__c = campusEdit
                );
                addrDirty = true;
            }
        }

        try {
            if (acctDirty && acct != null) {
                if (!Schema.sObjectType.Account.isUpdateable()) {
                    throw new KenCrudException('Account is not updateable by the current user.');
                }
                update acct;
            }
            if (crUpdDirty && crUpd != null) {
                if (!Schema.sObjectType.ConstituentRole.isUpdateable()) {
                    throw new KenCrudException('ConstituentRole is not updateable by the current user.');
                }
                update crUpd;
            }
            if (empDirty && empUpd != null) {
                if (!Schema.sObjectType.PersonEmployment.isCreateable() || !Schema.sObjectType.PersonEmployment.isUpdateable()) {
                    throw new KenCrudException('PersonEmployment is not upsertable by the current user.');
                }
                upsert empUpd;
            }
            if (addrDirty && addrUpd != null) {
                if (!Schema.sObjectType.Ken_Address__c.isCreateable() || !Schema.sObjectType.Ken_Address__c.isUpdateable()) {
                    throw new KenCrudException('Ken_Address__c is not upsertable by the current user.');
                }
                upsert addrUpd;
            }
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    /**
     * Sends a one-off email to the alumnus's personal email from the
     * "Alumni Management" org-wide address when configured.
     */
    @AuraEnabled
    public static void sendEmailToAlumni(Id recordId, String subjectText, String bodyText) {
        if (recordId == null || String.isBlank(subjectText) || String.isBlank(bodyText)) {
            throw new AuraHandledException('Subject and message are required.');
        }
        AlumniContext ctx = loadContext(recordId);
        String toAddr = (ctx.acct != null) ? ctx.acct.PersonEmail : null;
        if (String.isBlank(toAddr)) {
            throw new AuraHandledException('This alumnus has no email address on file.');
        }
        KenMessagingService.Request routing =
            new KenMessagingService.Request(KenMessagingService.TYPE_ADHOC_EMAIL)
                .toContact(toAddr, ctx.acct.PersonMobilePhone)
                .attribute('emailSubject', subjectText)
                .attribute('emailBody', bodyText);

        KenMessagingService.sendToPhoneChannels(routing);
        if (KenMessagingService.send(routing).handled) {
            return;
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toAddr });
        mail.setSubject(subjectText);
        mail.setHtmlBody(bodyText.escapeHtml4().replace('\n', '<br/>'));
        mail.setSaveAsActivity(false);
        List<OrgWideEmailAddress> owa = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE DisplayName = :KenMessagingService.orgWideAddressName()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!owa.isEmpty()) {
            mail.setOrgWideEmailAddressId(owa[0].Id);
        }
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
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
                WITH USER_MODE
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
                WITH USER_MODE
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

    /**
     * Saves the Academic Record edit grid. Rows arriving with no id that match a
     * row already on file — or another new row in the same submission — resolve
     * onto the existing record instead of inserting a duplicate, keyed on
     * institute + degree + completion year. ContactId is mirrored because only
     * that side of PersonEducation is related-list enabled.
     */
    @AuraEnabled
    public static void saveEducationRows(Id recordId, String rowsJson, String deleteIdsJson) {
        Id personAcctId = (recordId == null) ? null : lookupPersonAccountId(recordId);
        if (personAcctId == null) throw new AuraHandledException('No Person Account linked to this alumnus.');

        List<EducationEditRow> rows = String.isBlank(rowsJson)
            ? new List<EducationEditRow>()
            : (List<EducationEditRow>) JSON.deserialize(rowsJson, List<EducationEditRow>.class);

        Map<String, Id> existingByKey = existingEducationKeys(personAcctId);
        Set<String> seenKeys = new Set<String>();

        Id personContactId = null;
        for (Account a : [SELECT PersonContactId FROM Account WHERE Id = :personAcctId WITH USER_MODE LIMIT 1]) {
            personContactId = a.PersonContactId;
        }

        List<PersonEducation> toUpsert = new List<PersonEducation>();
        for (EducationEditRow r : rows) {
            // Skip fully-empty new rows.
            if (String.isBlank(r.id) && String.isBlank(r.institute) && String.isBlank(r.degree)
                && String.isBlank(r.grade) && String.isBlank(r.yearOfCompletion)) continue;
            String rowId = blankToNull(r.id);
            if (rowId == null) {
                String key = educationKey(r.institute, r.degree, r.yearOfCompletion);
                if (key != null) {
                    if (seenKeys.contains(key)) continue;
                    seenKeys.add(key);
                    if (existingByKey.containsKey(key)) rowId = existingByKey.get(key);
                }
            }
            PersonEducation pe = (rowId == null)
                ? new PersonEducation(AccountId = personAcctId, Is_Archived__c = false)
                : new PersonEducation(Id = (Id) rowId);
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
            if (personContactId != null) pe.ContactId = personContactId;
            toUpsert.add(pe);
        }

        try {
            if (!toUpsert.isEmpty()) {
                if (!Schema.sObjectType.PersonEducation.isCreateable() || !Schema.sObjectType.PersonEducation.isUpdateable()) {
                    throw new KenCrudException('PersonEducation is not upsertable by the current user.');
                }
                upsert toUpsert;
            }
            deleteChildren('PersonEducation', personAcctId, deleteIdsJson);
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    /**
     * Identity key for an education row: institute + degree + completion year,
     * case- and whitespace-insensitive. Returns null when there is nothing
     * meaningful to match on, so blank rows are never treated as duplicates.
     */
    private static String educationKey(String institute, String degree, String yearOfCompletion) {
        String inst = blankToNull(institute);
        String deg = blankToNull(degree);
        if (inst == null && deg == null) return null;
        return ((inst == null) ? '' : inst.trim().toLowerCase())
            + '|' + ((deg == null) ? '' : deg.trim().toLowerCase())
            + '|' + ((blankToNull(yearOfCompletion) == null) ? '' : yearOfCompletion.trim());
    }

    /** Maps the alumnus's unarchived education rows by identity key. */
    private static Map<String, Id> existingEducationKeys(Id personAcctId) {
        Map<String, Id> out = new Map<String, Id>();
        if (personAcctId == null) return out;
        for (PersonEducation pe : [
            SELECT Id, Institute_Name__c, Degree_Name__c, Year_of_Completion__c
            FROM PersonEducation
            WHERE AccountId = :personAcctId
            AND (Is_Archived__c = false OR Is_Archived__c = null)
            WITH USER_MODE
            LIMIT 200
        ]) {
            String key = educationKey(pe.Institute_Name__c, pe.Degree_Name__c, pe.Year_of_Completion__c);
            if (key != null && !out.containsKey(key)) out.put(key, pe.Id);
        }
        return out;
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
            if (!toUpsert.isEmpty()) {
                if (!Schema.sObjectType.PersonEmployment.isCreateable() || !Schema.sObjectType.PersonEmployment.isUpdateable()) {
                    throw new KenCrudException('PersonEmployment is not upsertable by the current user.');
                }
                upsert toUpsert;
            }
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
        List<SObject> rows = Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'ids' => ids, 'personAcctId' => personAcctId },
            AccessLevel.SYSTEM_MODE
        );
        if (!rows.isEmpty()) {
            Database.delete(rows, true, AccessLevel.USER_MODE);
        }
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
            CrmView r = resolveCrmRow(recordId);
            if (r == null) return emptyHeader();

            // ConstituentRole stage / registration status (separate query — standard sObject)
            // Stage label comes from KenLeadLifecycleService.resolveStage() — the
            // single source of truth for the 7-stage lifecycle (Lead/Unverified/
            // Registered/Onboarding In Progress/Active),
            // the same logic backing the admin dashboard KPIs and lifecycle funnel —
            // so this record's status matches what's shown everywhere else.
            String stageLabel = null;
            String enrollmentYear = null;
            ConstituentRole roleRow = resolveRoleRow(r);
            if (roleRow != null) {
                try { stageLabel = KenLeadLifecycleService.resolveStage(roleRow); } catch (Exception innerEx) { /* leave stage null */ }
                enrollmentYear = roleRow.Year_of_Enrollment__c;
            }

            HeaderDTO h = new HeaderDTO();
            h.alumniId = r.id;
            h.personAccountId = r.personAccountId;
            h.name = (r.person != null && r.person.Name != null) ? r.person.Name : r.name;
            h.initials = computeInitials(h.name);
            if (r.person != null) {
                try { h.photoUrl = (String) r.person.get(KenNamespaceUtil.qualifyCustom('Profile_Photo_URL__c')); } catch (Exception ex) { /* ignore */ }
            }
            h.role = 'ALUMNUS';
            h.registrationNumber = r.registrationNumber;
            h.classOf = r.graduationYear;
            h.program = displayProgram(r.program);
            // programDates: year of enrollment — year of graduation
            if (String.isNotBlank(enrollmentYear) && r.graduationYear != null) {
                h.programDates = enrollmentYear + ' – ' + r.graduationYear;
            } else if (r.graduationYear != null) {
                h.programDates = r.graduationYear;
            }
            h.yearsOut = (r.graduationYear != null) ? yearsOutLabel(r.graduationYear) : null;
            h.school = null;       // no school field in data model
            h.campus = r.currentLocation;
            Boolean isActive = (r.isActive == true);
            h.status = stageLabel;
            h.legacyId = null;     // no legacy id field
            h.badges = new List<BadgeDTO>();
            if (isActive) h.badges.add(badge('Active', 'emerald'));
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
                    WITH USER_MODE
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
                WITH USER_MODE
                ];
            } catch (Exception ex) { eventsCount = 0; }
            try {
                activeMentees = [
                    SELECT COUNT()
                    FROM Ken_Mentorship__c
                    WHERE Mentor__c = :personAcctId
                      AND Mentorship_Status__c IN ('Accepted', 'Scheduled')
                WITH USER_MODE
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
            CrmView r = resolveCrmRow(recordId);
            if (r == null) return emptyOverview();

            // Current employment (for snapshot block)
            PersonEmployment cur;
            if (r.personAccountId != null) {
                try {
                    List<PersonEmployment> peList = [
                        SELECT Designation__c, Job_Role__c, Company_Name__c, Location__c,
                               StartDate, EndDate, Currently_Employed__c, Is_Archived__c
                        FROM PersonEmployment
                        WHERE AccountId = :r.personAccountId
                        WITH USER_MODE
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
            if (String.isBlank(employerLine)) employerLine = r.currentCompany;

            String yearsOut = (r.graduationYear != null) ? yearsOutLabel(r.graduationYear) : null;

            // Year of Enrollment lives on the ConstituentRole (not the CRM); bulk-imported
            // CRM rows may carry no role link, so fall back to the person's latest role.
            String yearOfEnrollment = null;
            ConstituentRole enrollmentRole = resolveRoleRow(r);
            if (enrollmentRole != null) yearOfEnrollment = enrollmentRole.Year_of_Enrollment__c;

            OverviewDTO o = new OverviewDTO();
            o.snapshot = new List<KeyValue>{
                kv('Alumni status',     r.isActive == true ? 'Active · Engaged' : 'Inactive', null),
                kv('Registration number', r.registrationNumber,                                null),
                kv('Year of Enrollment', yearOfEnrollment,                                     null),
                kv('Class of',          r.graduationYear,                                      null),
                kv('Program',           displayProgram(r.program),                             null),
                kv('Years post-grad',   yearsOut,                                              null),
                kv('Current employer',  employerLine,                                          null),
                kv('Current role',      roleLine,                                              null)
            };

            AddressParts address = new AddressParts();
            String dob = null;
            String phone = null, emailPersonal = null, linkedIn = null, twitter = null;
            if (r.person != null) {
                address.street  = r.person.PersonMailingStreet;
                address.city    = r.person.PersonMailingCity;
                address.state   = r.person.PersonMailingState;
                address.postal  = r.person.PersonMailingPostalCode;
                address.country = r.person.PersonMailingCountry;
                if (r.person.PersonBirthdate != null) {
                    Date bd = r.person.PersonBirthdate;
                    dob = Datetime.newInstance(bd.year(), bd.month(), bd.day()).format('dd MMM yyyy');
                }
                phone         = r.person.PersonMobilePhone;
                emailPersonal = r.person.PersonEmail;
                linkedIn      = r.person.Linkedin_Profile_URL__c;
                try { twitter = (String) r.person.get(KenNamespaceUtil.qualifyCustom('Twitter_Profile_URL__c')); } catch (Exception ex) { /* ignore */ }
            }
            if (address.isEmpty() && r.personAccountId != null) {
                address = kenAddressFallback(r.personAccountId);
            }
            // Bio fields — only read from real Account fields, never hardcoded.
            String nationality = null;
            String languages   = null;
            if (r.person != null) {
                // Nationality__c is where registration/onboarding writes; the
                // KJS-only Nationality__pc variant is a legacy-data fallback.
                try { nationality = (String) r.person.get(KenNamespaceUtil.qualifyCustom('Nationality__c')); } catch (Exception ex) { /* field may not exist */ }
                if (String.isBlank(nationality)) {
                    try { nationality = (String) r.person.get('Nationality__pc'); } catch (Exception ex) { /* ignore */ }
                }
                // Languages — read from Languages_Known__c if the org has it.
                try { languages = (String) r.person.get(KenNamespaceUtil.qualifyCustom('Languages_Known__c')); } catch (Exception ex) { /* ignore */ }
            }
            String gender = null;
            String bloodGroup = null;
            if (r.person != null) {
                try { gender = (String) r.person.get('PersonGenderIdentity'); } catch (Exception ex) { /* ignore */ }
                try { bloodGroup = (String) r.person.get(KenNamespaceUtil.qualifyCustom('Blood_Group__c')); } catch (Exception ex) { /* ignore */ }
            }
            o.personalContact = new List<KeyValue>{
                kv('Phone',            phone,         null),
                kv('Email (personal)', emailPersonal, null),
                kv('Email (alumni)',   emailPersonal, null),
                kv('LinkedIn',         linkedIn,      null),
                kv('Twitter',          twitter,       null),
                kv('Date of birth',    dob,           null),
                kv('Gender',           gender,        null),
                kv('Blood group',      bloodGroup,    null),
                kv('Nationality',      nationality,   null),
                kv('Languages',        languages,     null),
                // Address is stored component-by-component, so surface it that
                // way instead of flattening it into one comma-joined line.
                kv('City',             address.city,    null),
                kv('State',            address.state,   null),
                kv('Country',          address.country, null)
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
            CrmView r = resolveCrmRow(recordId);
            if (r != null) {
                personAcctId = r.personAccountId;
                String prog  = (r.program != null)            ? displayProgram(r.program) : 'Program';
                String year  = (r.graduationYear != null)     ? r.graduationYear  : '—';
                String regNo = (r.registrationNumber != null) ? r.registrationNumber : null;
                a.graduationFooter = 'Graduated ' + year + ' · ' + prog
                    + (regNo != null ? ' · ' + regNo : '');
            }
        } catch (Exception e) { /* swallow */ }

        if (personAcctId == null) return a;

        try {
            for (PersonEducation pe : [
                SELECT Institute_Name__c, Degree_Name__c, Grade__c, Grade_Type__c, Year_of_Completion__c,
                       Program_Plan__r.Name, Program_Plan__r.Provider.Name
                FROM PersonEducation
                WHERE AccountId = :personAcctId
                AND (Is_Archived__c = false OR Is_Archived__c = null)
                WITH USER_MODE
                ORDER BY Year_of_Completion__c DESC NULLS LAST
                LIMIT 50
            ]) {
                EducationRow er = new EducationRow();
                // Institute_Name__c is free text the alumnus types, so an own-institute row can
                // arrive blank; the programme's provider is the reliable name in that case.
                er.institute = String.isNotBlank(pe.Institute_Name__c)
                    ? pe.Institute_Name__c
                    : (pe.Program_Plan__r != null && pe.Program_Plan__r.Provider != null
                        ? pe.Program_Plan__r.Provider.Name
                        : null);
                er.program   = (pe.Program_Plan__r != null) ? pe.Program_Plan__r.Name : null;
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
                WITH USER_MODE
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
                WITH USER_MODE
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
                    WITH USER_MODE
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
                SELECT Id, Mentee__c, Mentor__c, Mentorship_Status__c, Meet_Start_DateTime__c,
                       Meeting_Title__c, Meeting_Mode__c,
                       Mentee__r.Name
                FROM Ken_Mentorship__c
                WHERE Mentor__c = :personAcctId
                WITH USER_MODE
                ORDER BY Meet_Start_DateTime__c DESC NULLS LAST
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
                    Date meetDay = KenDateTimeUtil.localDate(m.Meet_Start_DateTime__c);
                    if (meetDay != null && (earliest == null || meetDay < earliest)) earliest = meetDay;
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
        return emptySupport();
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
        CrmView crm = resolveCrmRow(recordId);
        if (crm != null) personAcctId = crm.personAccountId;

        // ----- RECENT ACTIVITY: pick the 5 most recent signals -----
        List<Map<String, Object>> signals = new List<Map<String, Object>>();
        if (crm != null && crm.lastModifiedDate != null) {
            signals.add(new Map<String, Object>{
                'icon' => 'star',
                'title' => 'Profile updated',
                'date' => crm.lastModifiedDate
            });
        }
        if (personAcctId != null) {
            try {
                List<Ken_Event_Booking__c> evb = [
                    SELECT Id, CreatedDate FROM Ken_Event_Booking__c
                    WHERE Person_Account__c = :personAcctId
                    WITH USER_MODE
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
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC LIMIT 1
                ];
                if (!mn.isEmpty()) signals.add(new Map<String, Object>{
                    'icon' => 'mentor', 'title' => 'Mentor session logged', 'date' => mn[0].CreatedDate
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
        Boolean employerOk = false;
        Boolean emailOk = false;
        Boolean photoOk = false;
        Boolean linkedinOk = false;
        if (personAcctId != null) {
            try {
                Integer cnt = [
                    SELECT COUNT()
                    FROM PersonEmployment
                    WHERE AccountId = :personAcctId
                      AND Currently_Employed__c = true
                      AND Is_Archived__c = false
                WITH USER_MODE
                ];
                employerOk = (cnt > 0);
            } catch (Exception ex) { employerOk = false; }
            try {
                Boolean hasBounceField = Account.SObjectType.getDescribe().fields.getMap().containsKey('PersonEmailBouncedDate');
                String emailSoql = hasBounceField
                    ? 'SELECT PersonEmail, PersonEmailBouncedDate, Profile_Photo_URL__c, Linkedin_Profile_URL__c FROM Account WHERE Id = :personAcctId LIMIT 1'
                    : 'SELECT PersonEmail, Profile_Photo_URL__c, Linkedin_Profile_URL__c FROM Account WHERE Id = :personAcctId LIMIT 1';
                List<Account> emailAccts = Database.query(emailSoql);
                if (!emailAccts.isEmpty()) {
                    emailOk = emailAccts[0].get('PersonEmail') != null
                        && (!hasBounceField || emailAccts[0].get('PersonEmailBouncedDate') == null);
                    photoOk = String.isNotBlank((String) emailAccts[0].get(KenNamespaceUtil.qualifyCustom('Profile_Photo_URL__c')));
                    linkedinOk = String.isNotBlank((String) emailAccts[0].get(KenNamespaceUtil.qualifyCustom('Linkedin_Profile_URL__c')));
                }
            } catch (Exception ex) { emailOk = false; }
        }
        Boolean mentorOk = false;
        if (personAcctId != null) {
            try {
                Integer pCnt = [
                    SELECT COUNT()
                    FROM Ken_Alumni_Preferences__c
                    WHERE Person_Account__c = :personAcctId
                      AND Willing_to_be_a_mentor__c = true
                WITH USER_MODE
                ];
                mentorOk = (pCnt > 0);
            } catch (Exception ex) { mentorOk = false; }
        }
        r.recordHealth.add(rh('Alumni email active',            emailOk,         emailOk         ? null : 'Missing or bounced'));
        r.recordHealth.add(rh('Employer current and verified',  employerOk,      employerOk      ? null : 'No current employment'));
        r.recordHealth.add(rh('Profile photo added',            photoOk,         photoOk         ? null : 'Missing'));
        r.recordHealth.add(rh('LinkedIn profile linked',        linkedinOk,      linkedinOk      ? null : 'Not linked'));
        r.recordHealth.add(rh('Mentor profile complete',        mentorOk,        mentorOk        ? null : 'Not opted-in'));
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
       The modal opens with a ConstituentRole Id (or a Person Account Id
       from older links), so the resolver accepts either prefix.
       loadContext() detects whichever Id type was passed and returns
       the populated SObjects (cr / acct). resolveCrmRow() assembles a
       CrmView from them, so section code has one flat object to read.
       ============================================================ */
    @TestVisible
    private class AlumniContext {
        ConstituentRole cr;
        Account acct;
        Id personAccountId;
    }

    /**
     * Flat, in-memory view of an alumnus assembled from ConstituentRole,
     * Account, PersonEmployment and the Mailing address. This replaced
     * Ken_Alumni_CRM__c, which the 360 used as a carrier object rather
     * than as storage.
     */
    @TestVisible
    private class CrmView {
        public Id id;
        public Id roleId;
        public Id personAccountId;
        public Account person;
        public String name;
        public String program;
        public String graduationYear;
        public String registrationNumber;
        public String currentLocation;
        public String currentCompany;
        public Boolean isActive;
        public Datetime lastModifiedDate;
    }

    @TestVisible
    private static AlumniContext loadContext(Id recordId) {
        AlumniContext ctx = new AlumniContext();
        if (recordId == null) return ctx;
        String prefix = String.valueOf(recordId).substring(0, 3);
        String crPrefix   = Schema.ConstituentRole.SObjectType.getDescribe().getKeyPrefix();
        String acctPrefix = Schema.Account.SObjectType.getDescribe().getKeyPrefix();

        Id crId = null, acctId = null;
        if (prefix == crPrefix)        crId   = recordId;
        else if (prefix == acctPrefix) acctId = recordId;

        if (crId != null) {
            try {
                List<ConstituentRole> rows = [
                    SELECT Id, RoleType, Status, Registration_Status__c, PersonId,
                           Graduation_Year__c, Registration_Number__c, Program_Name__c,
                           Program_Plan__r.Name, Source_Funnel__c, CreatedDate, LastModifiedDate
                    FROM ConstituentRole WHERE Id = :crId
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!rows.isEmpty()) {
                    ctx.cr = rows[0];
                    if (acctId == null) acctId = ctx.cr.PersonId;
                }
            } catch (Exception ignored) {}
        }

        if (acctId != null) {
            try {
                String acctSoql =
                    'SELECT Id, Name, FirstName, LastName, PersonEmail, PersonMobilePhone, ' +
                    'PersonBirthdate, PersonMailingCountry, PersonMailingStreet, ' +
                    'PersonMailingCity, PersonMailingState, PersonMailingPostalCode, ' +
                    'Linkedin_Profile_URL__c, Twitter_Profile_URL__c, ' +
                    'Profile_Photo_URL__c, LastModifiedDate';
                Map<String, Schema.SObjectField> acctFieldMap = Account.SObjectType.getDescribe().fields.getMap();
                for (String optionalField : SYNTH_BIO_FIELDS) {
                    if (acctFieldMap.containsKey(optionalField)) acctSoql += ', ' + optionalField;
                }
                acctSoql += ' FROM Account WHERE Id = :acctId LIMIT 1';
                List<Account> rows = (List<Account>) Database.queryWithBinds(
                    acctSoql,
                    new Map<String, Object>{ 'acctId' => acctId },
                    AccessLevel.SYSTEM_MODE
                );
                if (!rows.isEmpty()) ctx.acct = rows[0];
            } catch (Exception ignored) {}
        }

        ctx.personAccountId = acctId;
        return ctx;
    }

    /**
     * Assemble the flat CrmView for this recordId (role or account Id):
     * academic facts from the ConstituentRole, person facts from the Account,
     * and current company / location resolved live from PersonEmployment and
     * the Mailing address via KenAlumniProfileService.
     */
    @TestVisible
    private static CrmView resolveCrmRow(Id recordId) {
        AlumniContext ctx = loadContext(recordId);
        if (ctx.cr == null && ctx.acct == null) return null;

        CrmView v = new CrmView();
        if (ctx.cr != null) {
            v.id = ctx.cr.Id;
            v.roleId = ctx.cr.Id;
            String prog = ctx.cr.Program_Name__c;
            if (String.isBlank(prog) && ctx.cr.Program_Plan__r != null) prog = ctx.cr.Program_Plan__r.Name;
            v.program = prog;
            v.graduationYear = ctx.cr.Graduation_Year__c;
            v.registrationNumber = ctx.cr.Registration_Number__c;
            v.isActive = ctx.cr.Status != 'Former';
            v.lastModifiedDate = ctx.cr.LastModifiedDate;
        }
        if (ctx.acct != null) {
            v.personAccountId = ctx.acct.Id;
            v.person = ctx.acct;
            v.name = ctx.acct.Name;
            if (v.id == null) v.id = ctx.acct.Id;
        }
        if (v.personAccountId != null) {
            try {
                KenAlumniProfileService.EmploymentSnapshot emp =
                    KenAlumniProfileService.currentEmployment(v.personAccountId);
                if (emp != null) v.currentCompany = emp.company;
                v.currentLocation = KenAlumniProfileService.currentLocation(v.personAccountId);
            } catch (Exception ignored) { /* render without employment/location */ }
        }
        return v;
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
    /**
     * Resolves the ConstituentRole backing a view. Falls back to the person's
     * most recent alumni role so stage and Year of Enrollment still render
     * when the view was assembled from an Account Id.
     */
    private static ConstituentRole resolveRoleRow(CrmView r) {
        try {
            if (r.roleId != null) {
                List<ConstituentRole> rows = [
                    SELECT Id, RoleType, Status, Registration_Status__c, Source_Funnel__c, Year_of_Enrollment__c
                    FROM ConstituentRole
                    WHERE Id = :r.roleId
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!rows.isEmpty()) return rows[0];
            }
            if (r.personAccountId != null) {
                List<ConstituentRole> rows = [
                    SELECT Id, RoleType, Status, Registration_Status__c, Source_Funnel__c, Year_of_Enrollment__c
                    FROM ConstituentRole
                    WHERE PersonId = :r.personAccountId AND RoleType = 'Alumni'
                    WITH USER_MODE
                    ORDER BY Last_Login__c DESC NULLS LAST, CreatedDate DESC, Id DESC
                    LIMIT 1
                ];
                if (!rows.isEmpty()) return rows[0];
            }
        } catch (Exception ignored) { /* render without role data */ }
        return null;
    }

    private static String displayProgram(String rawValue) {
        if (String.isBlank(rawValue)) return rawValue;
        String s = rawValue.trim();
        // Salesforce Ids are 15 or 18 chars and alphanumeric.
        if ((s.length() == 15 || s.length() == 18) && s.startsWith('0uF')) {
            try {
                Id pid = (Id) s;
                List<LearningProgramPlan> p = [SELECT Name FROM LearningProgramPlan WHERE Id = :pid WITH USER_MODE LIMIT 1];
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

    /**
     * The address is always stored one component per field, so it travels to
     * the LWC the same way — each part is its own labelled row.
     */
    private class AddressParts {
        String street;
        String city;
        String state;
        String postal;
        String country;
        Boolean isEmpty() {
            return String.isBlank(street) && String.isBlank(city) && String.isBlank(state)
                && String.isBlank(postal) && String.isBlank(country);
        }
    }

    /**
     * Onboarding stores the mailing address on Ken_Address__c (not the standard
     * PersonMailing* compound), so fall back to that row when the Account
     * address is empty. Read-only fallback — edits still write PersonMailing*.
     */
    private static AddressParts kenAddressFallback(Id personAccountId) {
        AddressParts parts = new AddressParts();
        try {
            List<Ken_Address__c> rows = [
                SELECT Street__c, City__c, State__c, Pincode__c, Country__c
                FROM Ken_Address__c
                WHERE Person_Account__c = :personAccountId
                  AND Address_Type__c = 'Mailing'
                WITH USER_MODE
                LIMIT 1
            ];
            if (rows.isEmpty()) return parts;
            parts.street  = rows[0].Street__c;
            parts.city    = rows[0].City__c;
            parts.state   = rows[0].State__c;
            parts.postal  = rows[0].Pincode__c;
            parts.country = rows[0].Country__c;
        } catch (Exception e) {
            /* leave the parts blank */
        }
        return parts;
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