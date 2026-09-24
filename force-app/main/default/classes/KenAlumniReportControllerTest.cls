@IsTest
private class KenAlumniReportControllerTest {

    private static final String EMAIL = 'ramesh.report@example.test';
    private static final Date DOB = Date.newInstance(1995, 6, 1);
    private static final Date EMPLOYED_FROM = Date.newInstance(2015, 1, 1);

    private static final Integer SLOT_TENTH = 0;
    private static final Integer SLOT_TWELFTH = 1;
    private static final Integer SLOT_BACHELORS = 2;
    private static final Integer SLOT_MASTERS = 3;

    private static Integer chunksConsumed = 0;

    private static Id personRecordTypeId() {
        for (RecordType rt : [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1
        ]) { return rt.Id; }
        return null;
    }

    private static Account person(String first, String last, String email) {
        Id recordTypeId = personRecordTypeId();
        Account account = new Account();
        if (recordTypeId != null) {
            account.RecordTypeId = recordTypeId;
            account.FirstName = first;
            account.LastName = last;
            account.PersonEmail = email;
        } else {
            account.Name = first + ' ' + last;
        }
        return account;
    }

    private static void assignCampus(SObject record) {
        if (!record.getSObjectType().getDescribe().fields.getMap().containsKey('campus__c')) return;
        Schema.Location campus = new Schema.Location(Name = 'Report Test Campus');
        for (Schema.PicklistEntry entry : Schema.Location.LocationType.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                campus.LocationType = entry.getValue();
                break;
            }
        }
        insert campus;
        record.put('Campus__c', campus.Id);
    }

    /**
     * ConstituentRole.Institution_Name__c and Program_Name__c are formulas over
     * Program_Plan__r, so the institute and programme columns only carry a value
     * once this chain exists.
     */
    private static Id programPlan(String institute, String programme) {
        Account provider = new Account(Name = institute);
        insert provider;
        Learning learning = new Learning(Name = programme + ' Learning');
        insert learning;
        LearningProgram program = new LearningProgram(Name = programme, LearningId = learning.Id);
        assignCampus(program);
        insert program;
        LearningProgramPlan plan = new LearningProgramPlan(
            Name = programme + ' Plan', LearningProgramId = program.Id, ProviderId = provider.Id
        );
        insert plan;
        return plan.Id;
    }

    private static ConstituentRole role(Id personId, Id programPlanId, String registrationNumber) {
        ConstituentRole cr = new ConstituentRole(
            PersonId = personId,
            RoleType = 'Alumni',
            Program_Plan__c = programPlanId,
            Registration_Number__c = registrationNumber,
            Graduation_Year__c = '2018'
        );
        cr.put('Status', 'Active');
        return cr;
    }

    private static PersonEducation education(
        Id accountId, String degree, String institute, String grade, String gradeType, String year
    ) {
        return new PersonEducation(
            Name = degree.length() > 80 ? degree.substring(0, 80) : degree,
            AccountId = accountId,
            Degree_Name__c = degree,
            Institute_Name__c = institute,
            Grade__c = grade,
            Grade_Type__c = gradeType,
            Year_of_Completion__c = year,
            Is_Archived__c = false
        );
    }

    /** One alumnus with every related record the wide report reads. */
    private static void seedFullAlumnus() {
        Account holder = person('Ramesh', 'Ghatnatti', EMAIL);
        if (personRecordTypeId() != null) {
            holder.PersonMobilePhone = '9512345678';
            holder.PersonBirthdate = DOB;
            holder.Languages_Known__c = 'Kannada,Hindi,English';
            holder.Linkedin_Profile_URL__c = 'https://linkedin.test/in/ramesh';
        }
        insert holder;

        insert new Ken_Address__c(
            Person_Account__c = holder.Id,
            Address_Type__c = 'Mailing',
            Street__c = 'Ganesh Nagar, Ghatkopar',
            City__c = 'Mumbai',
            State__c = 'Maharashtra',
            Pincode__c = '400077',
            Country__c = 'India'
        );

        insert new PersonEmployment(
            Name = 'Infosys',
            AccountId = holder.Id,
            RelatedPersonId = holder.Id,
            Company_Name__c = 'Infosys',
            Designation__c = 'I.T Consultant',
            Location__c = 'Mysore',
            Industry__c = 'I.T',
            StartDate = EMPLOYED_FROM,
            Currently_Employed__c = true,
            Is_Archived__c = false
        );

        insert new List<PersonEducation>{
            education(holder.Id, '10th', 'S K Somaiya Vinay Mandir', '62', 'Percentage', '2010'),
            education(holder.Id, '12th', 'S K Somaiya Vinay Mandir', '65', 'Percentage', '2012'),
            education(holder.Id, 'Bachelor of Technology in Computer Engineering',
                'K J Somaiya College of Engineering', '9', 'CGPA', '2017'),
            education(holder.Id, 'Master of Business Administration', 'SIMSR', '8', 'CGPA', '2019')
        };

        ConstituentRole cr = role(
            holder.Id, programPlan('S K Somaiya Vinay Mandir', 'HSC - Science'), 'RPT-123456'
        );
        cr.Year_of_Enrollment__c = '2010';
        cr.Graduation_Year__c = '2012';
        insert cr;
    }

    /**
     * Walks the slices exactly as the dashboard does, so the test exercises the
     * same contract the browser relies on: header on the first slice only, and
     * stop on done / an empty slice / a null resume Id.
     */
    private static String buildCsv(String reportKey) {
        List<String> parts = new List<String>();
        Id afterId = null;
        Boolean done = false;
        chunksConsumed = 0;
        while (!done) {
            KenAlumniReportController.ReportChunk chunk =
                KenAlumniReportController.getReportChunk(reportKey, afterId);
            chunksConsumed++;
            if (chunk.headerLine != null) parts.add(chunk.headerLine);
            if (String.isNotBlank(chunk.csv)) parts.add(chunk.csv);
            afterId = chunk.lastId;
            done = chunk.done || chunk.rowsInChunk == 0 || afterId == null;
        }
        return String.join(parts, '\r\n');
    }

    private static List<String> splitCsv(String line) {
        List<String> cells = new List<String>();
        Boolean inQuotes = false;
        String current = '';
        Integer index = 0;
        while (index < line.length()) {
            String character = line.substring(index, index + 1);
            if (character == '"') {
                if (inQuotes && index + 1 < line.length() && line.substring(index + 1, index + 2) == '"') {
                    current += '"';
                    index++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (character == ',' && !inQuotes) {
                cells.add(current);
                current = '';
            } else {
                current += character;
            }
            index++;
        }
        cells.add(current);
        return cells;
    }

    @IsTest
    static void bothDownloadsAreAlwaysOffered() {
        Test.startTest();
        List<KenAlumniReportController.ReportOption> options = KenAlumniReportController.getReports();
        Test.stopTest();

        System.assertEquals(2, options.size(), 'Both downloads ship in every org, with no gate.');
        System.assertEquals(KenAlumniReportController.REPORT_ALL_FIELDS, options[0].key);
        System.assertEquals('All Fields', options[0].label);
        System.assertEquals(43, options[0].columnCount);
        System.assertEquals(KenAlumniReportController.PREFIX_ALL_FIELDS, options[0].filePrefix);

        System.assertEquals(KenAlumniReportController.REPORT_MINIMAL_FIELDS, options[1].key);
        System.assertEquals('Minimal Fields', options[1].label);
        System.assertEquals(6, options[1].columnCount);
        System.assertEquals(KenAlumniReportController.PREFIX_MINIMAL_FIELDS, options[1].filePrefix);
        System.assertEquals(
            new List<String>{
                'Registration_Number', 'Email_ID', 'Institute_Name', 'Program_Name',
                'Year_Of_Joining', 'Year_Of_Completion'
            },
            KenAlumniReportController.MINIMAL_FIELDS_HEADERS,
            'The minimal headers keep the exact names the receiving IT team asked for.'
        );
    }

    @IsTest
    static void allFieldsDownloadCarriesEveryColumnInOrder() {
        seedFullAlumnus();

        Test.startTest();
        String csv = buildCsv(KenAlumniReportController.REPORT_ALL_FIELDS);
        Test.stopTest();

        List<String> lines = csv.split('\r\n');
        System.assertEquals(2, lines.size(), 'One header line and one alumni row.');
        System.assertEquals(KenAlumniReportController.ALL_FIELDS_HEADERS, splitCsv(lines[0]),
            'The header line matches the requested format exactly.');

        List<String> cells = splitCsv(lines[1]);
        System.assertEquals(43, cells.size(), 'Every column is written, blank or not.');
        System.assertEquals(EMAIL, cells[0]);
        System.assertEquals('Ramesh', cells[1]);
        System.assertEquals('Ghatnatti', cells[2]);
        System.assertEquals('9512345678', cells[3]);
        System.assertEquals(KenAlumniReportController.formatDate(DOB), cells[4],
            'Date of birth uses the dd-MMM-yyyy form the format shows.');
        System.assertEquals('https://linkedin.test/in/ramesh', cells[8]);
        System.assertEquals('Kannada,Hindi,English', cells[9],
            'A value containing commas survives quoting.');
        System.assertEquals('Ganesh Nagar, Ghatkopar', cells[10]);
        System.assertEquals('Mumbai', cells[11]);
        System.assertEquals('Maharashtra', cells[12]);
        System.assertEquals('400077', cells[13]);
        System.assertEquals('India', cells[14]);
        System.assertEquals('S K Somaiya Vinay Mandir', cells[15], 'Institute Name');
        System.assertEquals('HSC - Science', cells[16]);
        System.assertEquals('RPT-123456', cells[17]);
        System.assertEquals('2010', cells[18]);
        System.assertEquals('2012', cells[19]);
        System.assertEquals('Infosys', cells[20]);
        System.assertEquals('Mysore', cells[21]);
        System.assertEquals('I.T', cells[22]);
        System.assertEquals('I.T Consultant', cells[23]);
        System.assertEquals(KenAlumniReportController.formatDate(EMPLOYED_FROM), cells[24]);

        System.assertEquals('S K Somaiya Vinay Mandir', cells[25], '10th School');
        System.assertEquals('62', cells[26]);
        System.assertEquals('Percentage', cells[27]);
        System.assertEquals('2010', cells[28]);

        System.assertEquals('S K Somaiya Vinay Mandir', cells[29], '12th School');
        System.assertEquals('65', cells[30]);
        System.assertEquals('Percentage', cells[31]);
        System.assertEquals('2012', cells[32]);

        System.assertEquals('K J Somaiya College of Engineering', cells[33], 'Bachelors Institute');
        System.assertEquals('Bachelor of Technology in Computer Engineering', cells[34]);
        System.assertEquals('9', cells[35]);
        System.assertEquals('CGPA', cells[36]);
        System.assertEquals('2017', cells[37]);

        System.assertEquals('SIMSR', cells[38], 'Masters Institute');
        System.assertEquals('Master of Business Administration', cells[39]);
        System.assertEquals('8', cells[40]);
        System.assertEquals('CGPA', cells[41]);
        System.assertEquals('2019', cells[42]);
    }

    @IsTest
    static void minimalFieldsDownloadCarriesTheSixHandoverColumns() {
        seedFullAlumnus();

        Test.startTest();
        String csv = buildCsv(KenAlumniReportController.REPORT_MINIMAL_FIELDS);
        Test.stopTest();

        List<String> lines = csv.split('\r\n');
        System.assertEquals(2, lines.size(), 'One header line and one alumni row.');
        System.assertEquals(KenAlumniReportController.MINIMAL_FIELDS_HEADERS, splitCsv(lines[0]));
        System.assertEquals(
            '"RPT-123456","' + EMAIL + '","S K Somaiya Vinay Mandir","HSC - Science","2010","2012"',
            lines[1],
            'Registration number leads, then email, institute, programme, joining and completion year.'
        );
    }

    /**
     * The browser assembles the file from repeated slices, so a run longer than
     * one slice must still produce every row exactly once, under one header.
     */
    @IsTest
    static void anExportLongerThanOneSliceStillCarriesEveryRowOnce() {
        Account first = person('Slice', 'One', 'slice.one@example.test');
        Account second = person('Slice', 'Two', 'slice.two@example.test');
        insert new List<Account>{ first, second };
        insert new List<ConstituentRole>{
            role(first.Id, null, 'RPT-SLICE-1'),
            role(second.Id, null, 'RPT-SLICE-2')
        };
        KenAlumniReportController.chunkAllFields = 1;

        Test.startTest();
        String csv = buildCsv(KenAlumniReportController.REPORT_ALL_FIELDS);
        Test.stopTest();

        System.assert(chunksConsumed >= 2, 'More than one slice was needed: ' + chunksConsumed);
        System.assertEquals(2, csv.countMatches('\r\n'), 'One header line plus both alumni rows.');
        System.assertEquals(1, csv.countMatches('"Email","First Name"'), 'Only one header line.');
        System.assertEquals(1, csv.countMatches('"RPT-SLICE-1"'), 'First row appears exactly once.');
        System.assertEquals(1, csv.countMatches('"RPT-SLICE-2"'), 'Second row appears exactly once.');
    }

    @IsTest
    static void chunkRequestsRejectAnUnknownKey() {
        String message = null;
        Test.startTest();
        try {
            KenAlumniReportController.getReportChunk('somethingElse', null);
        } catch (Exception e) {
            message = e.getMessage();
        }
        Test.stopTest();
        System.assertNotEquals(null, message, 'An unknown report key is rejected.');
        System.assert(message.contains('Unknown report'), 'The reason survives: ' + message);
    }

    @IsTest
    static void rowCountDrivesTheProgressBar() {
        seedFullAlumnus();
        Test.startTest();
        Integer total = KenAlumniReportController.getRowCount(
            KenAlumniReportController.REPORT_ALL_FIELDS
        );
        Test.stopTest();
        System.assertEquals(1, total, 'One alumni role was seeded.');
    }

    @IsTest
    static void schoolAndDegreeNamesPickTheirOwnColumnBlock() {
        System.assertEquals(SLOT_TENTH, KenAlumniReportController.educationSlot('10th'));
        System.assertEquals(SLOT_TENTH, KenAlumniReportController.educationSlot('SSLC'));
        System.assertEquals(SLOT_TENTH, KenAlumniReportController.educationSlot('Class 10 Secondary School'));
        System.assertEquals(SLOT_TWELFTH, KenAlumniReportController.educationSlot('12th'));
        System.assertEquals(SLOT_TWELFTH, KenAlumniReportController.educationSlot('HSC - Science'));
        System.assertEquals(SLOT_TWELFTH, KenAlumniReportController.educationSlot('Higher Secondary'));
        System.assertEquals(SLOT_MASTERS, KenAlumniReportController.educationSlot('Master of Business Administration'));
        System.assertEquals(SLOT_MASTERS, KenAlumniReportController.educationSlot('M.Tech'));
        System.assertEquals(SLOT_MASTERS, KenAlumniReportController.educationSlot('MBA'));
        System.assertEquals(SLOT_MASTERS, KenAlumniReportController.educationSlot('PhD in Physics'),
            'A doctorate has no column of its own, so it folds into the Masters block.');
        System.assertEquals(SLOT_BACHELORS, KenAlumniReportController.educationSlot('B.Sc'));
        System.assertEquals(SLOT_BACHELORS, KenAlumniReportController.educationSlot('Bachelor of Technology'));
        System.assertEquals(SLOT_BACHELORS, KenAlumniReportController.educationSlot('Diploma in Printing'),
            'An unrecognised qualification lands in the Bachelors block rather than being dropped.');
        System.assertEquals(SLOT_BACHELORS, KenAlumniReportController.educationSlot(null));
    }

    @IsTest
    static void theLaterCompletionYearWinsAContestedBlock() {
        List<PersonEducation> rows = new List<PersonEducation>{
            education(null, 'Bachelor of Arts', 'A', '7', 'CGPA', '2012'),
            education(null, 'Bachelor of Laws', 'B', '8', 'CGPA', '2016'),
            education(null, 'Bachelor of Commerce', 'C', '9', 'CGPA', null)
        };

        List<PersonEducation> slots = KenAlumniReportController.slotEducation(rows);
        System.assertEquals('Bachelor of Laws', slots[SLOT_BACHELORS].Degree_Name__c,
            'The most recent completion year keeps the block.');
        System.assertEquals(null, slots[SLOT_TENTH]);
        System.assertEquals(null, slots[SLOT_TWELFTH]);
        System.assertEquals(null, slots[SLOT_MASTERS]);
    }

    /**
     * ConstituentRole.PersonId is polymorphic: legacy roles can point at the
     * Person Account's Contact instead of the Account. Such a row used to
     * export with every personal column blank and no error.
     */
    @IsTest
    static void aContactAnchoredRoleStillExportsItsPersonalColumns() {
        Account account = person('Contact', 'Anchored', 'contact.anchored@example.test');
        insert account;
        Id personContactId = [SELECT PersonContactId FROM Account WHERE Id = :account.Id].PersonContactId;
        if (personContactId == null) return;

        ConstituentRole cr = role(
            account.Id, programPlan('S K Somaiya Vinay Mandir', 'Bachelor of Arts'), 'RPT-CONTACT'
        );
        cr.PersonId = personContactId;
        insert cr;

        Test.startTest();
        String csv = buildCsv(KenAlumniReportController.REPORT_ALL_FIELDS);
        Test.stopTest();

        String dataLine = csv.substring(csv.indexOf('\r\n') + 2);
        System.assert(dataLine.startsWith('"contact.anchored@example.test","Contact","Anchored"'),
            'A Contact-anchored role resolves to its Person Account: ' + dataLine);
        System.assert(dataLine.contains('"RPT-CONTACT"'), 'The role fields still export.');
    }

    @IsTest
    static void twoProgrammesForOnePersonProduceTwoRows() {
        Account account = person('Vipul', 'Sharma', 'vipul.report@example.test');
        insert account;
        Id engineering = programPlan(
            'K J Somaiya College of Engineering', 'Bachelor of Technology in Computer Engineering'
        );
        Id management = programPlan('SIMSR', 'Master of Management Studies');
        insert new List<ConstituentRole>{
            role(account.Id, engineering, 'RPT-A'),
            role(account.Id, management, 'RPT-B')
        };

        Test.startTest();
        String csv = buildCsv(KenAlumniReportController.REPORT_ALL_FIELDS);
        Test.stopTest();

        System.assertEquals(2, csv.countMatches('\r\n'),
            'A header line plus one row per alumni programme.');
        System.assert(csv.contains('"K J Somaiya College of Engineering","Bachelor of Technology in Computer Engineering","RPT-A"'),
            'Institute and programme resolve through the program plan.');
        System.assert(csv.contains('"SIMSR","Master of Management Studies","RPT-B"'),
            'The second programme reports its own institute.');
    }

    @IsTest
    static void anAlumnusWithNoRelatedRecordsStillExportsEveryColumn() {
        Account account = person('Sparse', 'Record', 'sparse.report@example.test');
        insert account;
        insert role(account.Id, null, 'RPT-SPARSE');

        Test.startTest();
        String csv = buildCsv(KenAlumniReportController.REPORT_ALL_FIELDS);
        Test.stopTest();

        String dataLine = csv.substring(csv.indexOf('\r\n') + 2);
        System.assertEquals(42, dataLine.countMatches('","'),
            'All 43 columns are present even when address, employment and education are empty.');
        System.assert(dataLine.contains('"RPT-SPARSE"'), 'The role fields still export.');
    }

    @IsTest
    static void anOrgWithNoAlumniStillProducesAHeaderOnlyFile() {
        Test.startTest();
        String csv = buildCsv(KenAlumniReportController.REPORT_ALL_FIELDS);
        Test.stopTest();

        System.assertEquals(0, csv.countMatches('\r\n'), 'Only the header line is written.');
        System.assert(csv.startsWith('"Email","First Name"'),
            'The header keeps the requested column order.');
    }

    @IsTest
    static void reportMetadataHelpersResolveBothReports() {
        System.assertEquals(43, KenAlumniReportController.headersFor(
            KenAlumniReportController.REPORT_ALL_FIELDS).size());
        System.assertEquals(6, KenAlumniReportController.headersFor(
            KenAlumniReportController.REPORT_MINIMAL_FIELDS).size());
        System.assertEquals(KenAlumniReportController.PREFIX_MINIMAL_FIELDS,
            KenAlumniReportController.filePrefix(KenAlumniReportController.REPORT_MINIMAL_FIELDS));
        System.assertEquals(KenAlumniReportController.PREFIX_ALL_FIELDS,
            KenAlumniReportController.filePrefix(KenAlumniReportController.REPORT_ALL_FIELDS));
        System.assert(
            KenAlumniReportController.chunkSize(KenAlumniReportController.REPORT_MINIMAL_FIELDS)
                > KenAlumniReportController.chunkSize(KenAlumniReportController.REPORT_ALL_FIELDS),
            'The narrow report reads more roles per slice than the wide one.');
        System.assertEquals('', KenAlumniReportController.formatDate(null));
        System.assert(Pattern.matches('^\\d{2}-\\w{3}-\\d{4}$',
                KenAlumniReportController.formatDate(DOB)),
            'Dates are written as dd-MMM-yyyy.');
        System.assertEquals('"a","b""c",""',
            KenAlumniReportController.toCsvLine(new List<String>{ 'a', 'b"c', null }),
            'Cells are quoted and embedded quotes doubled.');
    }
}