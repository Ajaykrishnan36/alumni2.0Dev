/**
 * Reusable lookups + formatting helpers for the group-feed surface area.
 * Kept thin in Slice 1; will host notification dispatch + scheduler logic in later slices.
 */
public without sharing class KenGroupFeedService {
  private static final String POLL_CATEGORY = 'Poll';
  private static final String POLL_QUESTION_TYPE = 'Multiple Choice';
  private static final String POLL_AUDIENCE = 'Group Members';

  public static Map<Id, String> lookupProfileImages(Set<Id> accountIds) {
    Map<Id, String> out = new Map<Id, String>();
    if (accountIds == null || accountIds.isEmpty())
      return out;
    String orgDomain = URL.getOrgDomainUrl().toExternalForm();
    for (Account a : [
      SELECT Id, Profile_Photo_URL__c, PhotoUrl
      FROM Account
      WHERE Id IN :accountIds
    WITH SECURITY_ENFORCED
    ]) {
      if (String.isNotBlank(a.Profile_Photo_URL__c)) {
        out.put(a.Id, a.Profile_Photo_URL__c);
      } else if (String.isNotBlank(a.PhotoUrl)) {
        out.put(a.Id, orgDomain + a.PhotoUrl);
      }
    }
    return out;
  }

  public static Map<Id, String> lookupBatchLabels(Set<Id> accountIds) {
    Map<Id, String> out = new Map<Id, String>();
    if (accountIds == null || accountIds.isEmpty())
      return out;
    for (ConstituentRole role : [
      SELECT PersonId, Graduation_Year__c
      FROM ConstituentRole
      WHERE PersonId IN :accountIds AND Graduation_Year__c != NULL
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
    ]) {
      if (!out.containsKey(role.PersonId)) {
        out.put(role.PersonId, 'Batch - ' + role.Graduation_Year__c);
      }
    }
    return out;
  }

  // --- Inline images in the post body -------------------------------------
  //
  // Chatter validates FeedItem.Body on insert and is far stricter than the
  // rich-text editor's output. Verified against the org, it accepts only:
  //   <p> <b> <i> <u> <s> <ul> <ol> <li> <a href target rel> <img src alt>
  // and rejects <div>, <br>, <font>, <strike>, plus any style/align/data-*
  // attribute, with INVALID_MARKUP. An <img> must reference a Salesforce file
  // as sfdc://<ContentDocumentId> - an external URL, or a ContentVersionId
  // instead of the document Id, fails with INVALID_CROSS_REFERENCE_KEY.
  //
  // So the body is normalized on the way in, and the sfdc:// references are
  // swapped for renderable URLs on the way out.

  private static final Pattern INLINE_IMG_DOC = Pattern.compile(
    '(?i)sfdc://(069[a-zA-Z0-9]{12,15})'
  );

  /**
   * Coerce rich-text-editor HTML into the subset Chatter accepts. Unsupported
   * markup is unwrapped rather than dropped, so the text always survives even
   * when its formatting cannot.
   */
  public static String normalizeRichText(String html) {
    if (String.isBlank(html))
      return html;
    String s = html;

    // Paragraph breaks: <br> and <div> are both rejected, <p> is not.
    s = s.replaceAll('(?i)<br\\s*/?>', '</p><p>');
    s = s.replaceAll('(?i)<div\\b[^>]*>', '<p>');
    s = s.replaceAll('(?i)</div\\s*>', '</p>');

    // Tags Chatter supports under a different name.
    s = s.replaceAll('(?i)<strong\\b[^>]*>', '<b>')
      .replaceAll('(?i)</strong\\s*>', '</b>');
    s = s.replaceAll('(?i)<em\\b[^>]*>', '<i>')
      .replaceAll('(?i)</em\\s*>', '</i>');
    s = s.replaceAll('(?i)<strike\\b[^>]*>', '<s>')
      .replaceAll('(?i)</strike\\s*>', '</s>');

    // Drop images that do not reference a Salesforce file - Chatter would
    // reject them and take the whole post down with them.
    s = s.replaceAll('(?i)<img\\b(?![^>]*src\\s*=\\s*"sfdc://)[^>]*>', '');
    // Keep src only on the images that remain.
    s = s.replaceAll(
      '(?i)<img\\b[^>]*src\\s*=\\s*"(sfdc://[^"]*)"[^>]*>',
      '<img src="$1"></img>'
    );

    // Anchors keep href only; target/rel are re-applied.
    s = s.replaceAll(
      '(?i)<a\\b[^>]*href\\s*=\\s*"([^"]*)"[^>]*>',
      '<a href="$1" target="_blank" rel="noopener noreferrer">'
    );
    s = s.replaceAll('(?i)<a\\b(?![^>]*href)[^>]*>', '');

    // Every other supported tag carries no attributes at all.
    s = s.replaceAll('(?i)<(p|b|i|u|s|ul|ol|li)\\b[^>]*>', '<$1>');

    // Unwrap anything still unsupported (<span>, <font>, <h1>, ...).
    s = s.replaceAll(
      '(?i)</?(?!(?:p|b|i|u|s|ul|ol|li|a|img)\\b)[a-z][a-z0-9]*\\b[^>]*>',
      ''
    );

    // The <br>/<div> rewrites above can leave empty paragraphs behind.
    s = s.replaceAll('(?i)<p>(?:\\s|&nbsp;)*</p>', '');
    return s.trim();
  }

  /** ContentDocumentIds referenced as sfdc:// inside a set of post bodies. */
  public static Set<Id> extractInlineImageIds(List<String> bodies) {
    Set<Id> out = new Set<Id>();
    if (bodies == null)
      return out;
    for (String b : bodies) {
      if (String.isBlank(b) || !b.contains('sfdc://'))
        continue;
      Matcher m = INLINE_IMG_DOC.matcher(b);
      while (m.find())
        out.add((Id) m.group(1));
    }
    return out;
  }

  /**
   * ContentDocumentId -> a URL the browser can actually render.
   *
   * The distribution link written at upload time is reused; a document without
   * one (an image carried over from the old attachment flow) gets a link minted
   * on first read. If public links are disabled org-wide the shepherd URL is
   * used, which renders on internal pages but not inside the portal.
   */
  public static Map<Id, String> lookupInlineImageUrls(Set<Id> documentIds) {
    Map<Id, String> out = new Map<Id, String>();
    if (documentIds == null || documentIds.isEmpty())
      return out;

    Map<Id, Id> documentByVersion = new Map<Id, Id>();
    for (ContentVersion cv : [
      SELECT Id, ContentDocumentId
      FROM ContentVersion
      WHERE ContentDocumentId IN :documentIds AND IsLatest = TRUE
    WITH SYSTEM_MODE
    ]) {
      documentByVersion.put(cv.Id, cv.ContentDocumentId);
    }
    if (documentByVersion.isEmpty())
      return out;

    for (ContentDistribution dist : [
      SELECT ContentVersionId, ContentDownloadUrl
      FROM ContentDistribution
      WHERE ContentVersionId IN :documentByVersion.keySet()
    WITH SYSTEM_MODE
    ]) {
      // ContentDownloadUrl is not filterable in SOQL, so it is checked here.
      if (String.isBlank(dist.ContentDownloadUrl))
        continue;
      out.put(
        documentByVersion.get(dist.ContentVersionId),
        dist.ContentDownloadUrl
      );
    }

    Set<Id> missing = new Set<Id>();
    for (Id versionId : documentByVersion.keySet()) {
      if (!out.containsKey(documentByVersion.get(versionId)))
        missing.add(versionId);
    }
    if (!missing.isEmpty()) {
      try {
        Map<Id, String> minted = KenCreateContentVersion.createDistributions(
          missing,
          false
        );
        for (Id versionId : minted.keySet()) {
          out.put(documentByVersion.get(versionId), minted.get(versionId));
        }
      } catch (Exception e) {
        // Reading the feed must not fail because a link could not be made.
        System.debug(
          LoggingLevel.ERROR,
          'Inline image distribution failed: ' + e.getMessage()
        );
      }
      for (Id versionId : missing) {
        Id docId = documentByVersion.get(versionId);
        if (!out.containsKey(docId)) {
          out.put(docId, '/sfc/servlet.shepherd/version/download/' + versionId);
        }
      }
    }
    return out;
  }

  /**
   * Swap every sfdc://<ContentDocumentId> for its rendition URL. Images whose
   * file has since been deleted are removed instead of left as a broken icon.
   */
  public static String rewriteInlineImages(
    String body,
    Map<Id, String> urlByDocument
  ) {
    if (String.isBlank(body) || !body.contains('sfdc://'))
      return body;
    String s = body;
    if (urlByDocument != null) {
      for (Id docId : urlByDocument.keySet()) {
        String url = urlByDocument.get(docId);
        // Also stamp the ContentDocumentId onto the tag as data-doc-id, so a feature
        // like "share this image" can identify which document an inline <img> came
        // from — the client only ever sees this rewritten URL, never the raw sfdc://
        // reference. This works by reusing the closing quote already present right
        // after "sfdc://<docId>" in the source markup: replacing that substring with
        // "<url>\" data-doc-id=\"<docId>" turns src="sfdc://<docId>" into
        // src="<url>" data-doc-id="<docId>" once the original trailing quote lands.
        String replacement = url + '" data-doc-id="' + docId;
        s = s.replace('sfdc://' + docId, replacement);
        s = s.replace(
          'sfdc://' + String.valueOf(docId).substring(0, 15),
          replacement
        );
      }
    }
    // Anything still unresolved points at a file that no longer exists.
    s = s.replaceAll(
      '(?i)<img\\b[^>]*src\\s*=\\s*"sfdc://[^"]*"[^>]*>(?:</img\\s*>)?',
      ''
    );
    return s;
  }

  public static Map<Id, List<KenGroupFeedController.AttachmentDTO>> lookupAttachments(
    Set<Id> feedItemIds,
    Map<Id, String> bodyByFeedItem
  ) {
    Map<Id, List<KenGroupFeedController.AttachmentDTO>> out = new Map<Id, List<KenGroupFeedController.AttachmentDTO>>();
    if (feedItemIds == null || feedItemIds.isEmpty())
      return out;

    Map<Id, Id> documentToFeedItem = new Map<Id, Id>();
    Set<Id> documentIds = new Set<Id>();
    for (ContentDocumentLink link : [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :feedItemIds
    WITH SYSTEM_MODE
    ]) {
      documentToFeedItem.put(link.ContentDocumentId, link.LinkedEntityId);
      documentIds.add(link.ContentDocumentId);
    }
    if (documentIds.isEmpty())
      return out;

    for (ContentVersion cv : [
      SELECT Id, ContentDocumentId, Title, FileType, FileExtension
      FROM ContentVersion
      WHERE ContentDocumentId IN :documentIds AND IsLatest = TRUE
    WITH SYSTEM_MODE
    ]) {
      Id feedItemId = documentToFeedItem.get(cv.ContentDocumentId);
      if (feedItemId == null)
        continue;
      // Skip files the body already renders inline - listing them again as
      // an attachment chip would show the same image twice.
      if (bodyByFeedItem != null) {
        String body = bodyByFeedItem.get(feedItemId);
        if (
          String.isNotBlank(body) &&
          body.contains('sfdc://' + cv.ContentDocumentId)
        )
          continue;
      }
      KenGroupFeedController.AttachmentDTO dto = new KenGroupFeedController.AttachmentDTO();
      dto.contentVersionId = cv.Id;
      dto.contentDocumentId = cv.ContentDocumentId;
      dto.fileName = cv.Title;
      dto.fileType = cv.FileType;
      dto.isImage = isImageType(cv.FileType, cv.FileExtension);
      dto.downloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
      dto.previewUrl = dto.isImage
        ? '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' +
          cv.Id
        : null;
      if (!out.containsKey(feedItemId))
        out.put(feedItemId, new List<KenGroupFeedController.AttachmentDTO>());
      out.get(feedItemId).add(dto);
    }
    return out;
  }

  private static Boolean isImageType(String fileType, String fileExtension) {
    if (String.isNotBlank(fileType)) {
      String f = fileType.toUpperCase();
      if (
        f == 'JPG' ||
        f == 'JPEG' ||
        f == 'PNG' ||
        f == 'GIF' ||
        f == 'WEBP' ||
        f == 'BMP' ||
        f == 'SVG'
      )
        return true;
    }
    if (String.isNotBlank(fileExtension)) {
      String ex = fileExtension.toLowerCase();
      if (
        ex == 'jpg' ||
        ex == 'jpeg' ||
        ex == 'png' ||
        ex == 'gif' ||
        ex == 'webp' ||
        ex == 'bmp' ||
        ex == 'svg'
      )
        return true;
    }
    return false;
  }

  // --- Group polls -----------------------------------------------------------
  //
  // A poll is a one-question AssessmentQuestionSet tagged with the feed post it
  // hangs off (Feed_Item__c) and the moment voting closes (Ends_At__c). Its
  // options are the question version's choices, and one vote is an Assessment
  // header carrying a single AssessmentQuestionResponse. The id the client knows
  // a poll by is the AssessmentQuestionVersion id, because that is what an answer
  // points at.

  /**
   * @description Everything a vote has to be checked against before it is stored.
   */
  public class PollContext {
    public Id questionSetId;
    public Id questionVersionId;
    public Id feedItemId;
    public Datetime endsAt;
    public String questionText;
    public Set<String> optionTexts;
  }

  /**
   * @description Stores a group poll's question and options as a one-question question set,
   *              tagged with the post it belongs to and the moment voting closes.
   * @param feedItemId Feed post the poll is attached to.
   * @param question Poll question.
   * @param options Option texts in display order.
   * @param durationDays Days the poll stays open.
   * @return Id of the question set holding the poll.
   */
  public static Id savePollQuestionSet(
    Id feedItemId,
    String question,
    List<String> options,
    Integer durationDays
  ) {
    List<KenAssessmentSurveyService.ChoiceRow> choices = new List<KenAssessmentSurveyService.ChoiceRow>();
    if (options != null) {
      for (String o : options) {
        if (String.isBlank(o))
          continue;
        KenAssessmentSurveyService.ChoiceRow choice = new KenAssessmentSurveyService.ChoiceRow();
        choice.value = o;
        choice.label = o;
        choices.add(choice);
      }
    }

    KenAssessmentSurveyService.QuestionInput input = new KenAssessmentSurveyService.QuestionInput();
    input.text = question;
    input.questionType = POLL_QUESTION_TYPE;
    input.required = true;
    input.choices = choices;

    Id questionSetId = KenAssessmentSurveyService.saveQuestionSet(
      null,
      question,
      new List<KenAssessmentSurveyService.QuestionInput>{ input }
    );

    if (!Schema.sObjectType.AssessmentQuestionSet.isUpdateable()) {
        throw new KenCrudException('AssessmentQuestionSet is not updateable by the current user.');
    }
    update new AssessmentQuestionSet(
      Id = questionSetId,
      Feed_Item__c = String.valueOf(feedItemId),
      Ends_At__c = Datetime.now()
        .addDays(durationDays == null ? 7 : durationDays)
    );
    return questionSetId;
  }

  /**
   * @description Resolves the post, deadline, wording and permitted options of one poll.
   * @param questionVersionId Question version the client knows the poll by.
   * @return Poll context, or null when the id does not identify a poll.
   */
  public static PollContext pollContext(Id questionVersionId) {
    if (questionVersionId == null)
      return null;

    List<AssessmentQuestionVersion> versionRows = [
      SELECT
        AssessmentQuestion.Ken_Question_Set__c,
        QuestionText,
        ResponseValues
      FROM AssessmentQuestionVersion
      WHERE Id = :questionVersionId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (versionRows.isEmpty())
      return null;

    List<AssessmentQuestionSet> sets = [
      SELECT Id, Feed_Item__c, Ends_At__c
      FROM AssessmentQuestionSet
      WHERE Id = :versionRows[0].AssessmentQuestion.Ken_Question_Set__c
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (sets.isEmpty())
      return null;

    PollContext ctx = new PollContext();
    ctx.questionSetId = sets[0].Id;
    ctx.questionVersionId = questionVersionId;
    ctx.feedItemId = toId(sets[0].Feed_Item__c);
    ctx.endsAt = sets[0].Ends_At__c;
    ctx.questionText = versionRows[0].QuestionText;
    ctx.optionTexts = new Set<String>();
    for (
      KenAssessmentSurveyService.ChoiceRow choice : KenAssessmentSurveyService.parseChoices(
        versionRows[0].ResponseValues
      )
    ) {
      String text = choiceText(choice);
      if (String.isNotBlank(text))
        ctx.optionTexts.add(text);
    }
    return ctx;
  }

  /**
   * @description Records one vote. A voter who has already answered has their existing answer
   *              rewritten, so a poll holds at most one submission per person.
   * @param questionVersionId Question version the client knows the poll by.
   * @param respondentAccountId Person Account casting the vote.
   * @param optionText Chosen option.
   * @param questionText Poll wording, used to name the submission.
   */
  public static void recordPollVote(
    Id questionVersionId,
    Id respondentAccountId,
    String optionText,
    String questionText
  ) {
    if (questionVersionId == null || respondentAccountId == null)
      return;

    List<AssessmentQuestionResponse> existing = [
      SELECT Id, AssessmentId
      FROM AssessmentQuestionResponse
      WHERE
        AssessmentQuestionId = :questionVersionId
        AND Assessment.Respondent__c = :respondentAccountId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      if (!Schema.sObjectType.AssessmentQuestionResponse.isUpdateable()) {
          throw new KenCrudException('AssessmentQuestionResponse is not updateable by the current user.');
      }
      update new AssessmentQuestionResponse(
        Id = existing[0].Id,
        ResponseText = optionText
      );
      if (existing[0].AssessmentId != null) {
        if (!Schema.sObjectType.Assessment.isUpdateable()) {
            throw new KenCrudException('Assessment is not updateable by the current user.');
        }
        update new Assessment(
          Id = existing[0].AssessmentId,
          Submitted_Date__c = System.now()
        );
      }
      return;
    }

    Assessment header = new Assessment(
      Name = pollLabel(questionText, 80),
      AssessmentStatus = 'Completed',
      Respondent__c = respondentAccountId,
      Response_Category__c = POLL_CATEGORY,
      Submitted_Date__c = System.now(),
      Ken_Module__c = KenAssessmentSurveyService.MODULE_TAG,
      EffectiveDateTime = System.now()
    );
    if (!Schema.sObjectType.Assessment.isCreateable()) {
        throw new KenCrudException('Assessment is not createable by the current user.');
    }
    insert header;

    if (!Schema.sObjectType.AssessmentQuestionResponse.isCreateable()) {
        throw new KenCrudException('AssessmentQuestionResponse is not createable by the current user.');
    }
    insert new AssessmentQuestionResponse(
      Name = pollLabel(questionText, 80),
      AssessmentId = header.Id,
      AssessmentQuestionId = questionVersionId,
      ResponseText = optionText,
      Question_Label__c = pollLabel(questionText, 255),
      Response_Category__c = POLL_CATEGORY
    );
  }

  /**
   * @description Removes everything a group poll owns when its post is deleted: the votes cast
   *              on it, their submission headers and the question set holding the question.
   *              Question versions are archived rather than deleted, which is all Salesforce
   *              allows once a version has been published.
   * @param feedItemId Feed post whose poll should be removed.
   */
  public static void deletePollData(Id feedItemId) {
    if (feedItemId == null)
      return;

    List<AssessmentQuestionSet> sets = pollSets(new Set<Id>{ feedItemId });
    if (sets.isEmpty())
      return;

    Set<Id> questionSetIds = new Set<Id>();
    for (AssessmentQuestionSet qSet : sets) {
      questionSetIds.add(qSet.Id);
    }

    Set<Id> versionIds = new Set<Id>();
    for (AssessmentQuestionVersion v : [
      SELECT Id
      FROM AssessmentQuestionVersion
      WHERE AssessmentQuestion.Ken_Question_Set__c IN :questionSetIds
    WITH SECURITY_ENFORCED
    ]) {
      versionIds.add(v.Id);
    }

    if (!versionIds.isEmpty()) {
      List<AssessmentQuestionResponse> answers = [
        SELECT Id, AssessmentId
        FROM AssessmentQuestionResponse
        WHERE AssessmentQuestionId IN :versionIds
      WITH SECURITY_ENFORCED
      ];
      Set<Id> headerIds = new Set<Id>();
      for (AssessmentQuestionResponse r : answers) {
        if (r.AssessmentId != null)
          headerIds.add(r.AssessmentId);
      }
      if (!answers.isEmpty()) {
        if (!Schema.sObjectType.AssessmentQuestionResponse.isDeletable()) {
          throw new KenCrudException('AssessmentQuestionResponse is not deletable by the current user.');
        }
        delete answers;
      }
      if (!headerIds.isEmpty()) {
        if (!Schema.sObjectType.Assessment.isDeletable()) {
          throw new KenCrudException('Assessment is not deletable by the current user.');
        }
        delete [SELECT Id FROM Assessment WHERE Id IN :headerIds WITH SECURITY_ENFORCED];
      }
    }

    for (Id questionSetId : questionSetIds) {
      KenAssessmentSurveyService.deleteSurveyData(questionSetId, null);
    }
  }

  /**
   * @description Builds the poll state each of the given posts should render, tallying every
   *              vote in memory because the answer text is a long text area and cannot be
   *              grouped in SOQL.
   * @param feedItemIds Posts to resolve polls for.
   * @param currentUserId User whose own vote should be flagged.
   * @return Map of post id to its poll state; posts without a poll are absent.
   */
  public static Map<Id, KenGroupFeedController.PollDTO> lookupPolls(
    Set<Id> feedItemIds,
    Id currentUserId
  ) {
    Map<Id, KenGroupFeedController.PollDTO> out = new Map<Id, KenGroupFeedController.PollDTO>();
    if (feedItemIds == null || feedItemIds.isEmpty())
      return out;

    List<AssessmentQuestionSet> sets = pollSets(feedItemIds);
    if (sets.isEmpty())
      return out;

    Map<Id, Id> feedItemBySet = new Map<Id, Id>();
    Map<Id, Datetime> endsAtBySet = new Map<Id, Datetime>();
    for (AssessmentQuestionSet qSet : sets) {
      Id feedItemId = toId(qSet.Feed_Item__c);
      if (feedItemId == null)
        continue;
      feedItemBySet.put(qSet.Id, feedItemId);
      endsAtBySet.put(qSet.Id, qSet.Ends_At__c);
    }
    if (feedItemBySet.isEmpty())
      return out;

    Map<Id, List<KenAssessmentSurveyService.QuestionRow>> questionsBySet = KenAssessmentSurveyService.questionsBySet(
      feedItemBySet.keySet()
    );

    Map<Id, Id> setByVersion = new Map<Id, Id>();
    for (Id questionSetId : questionsBySet.keySet()) {
      List<KenAssessmentSurveyService.QuestionRow> rows = questionsBySet.get(
        questionSetId
      );
      if (rows == null || rows.isEmpty())
        continue;
      setByVersion.put(rows[0].id, questionSetId);
    }
    if (setByVersion.isEmpty())
      return out;

    Id myAccountId = currentUserAccountId(currentUserId);
    Map<Id, Map<String, Integer>> votesByOptionPerPoll = new Map<Id, Map<String, Integer>>();
    Map<Id, Integer> totalVotesPerPoll = new Map<Id, Integer>();
    Map<Id, String> myVoteByPoll = new Map<Id, String>();

    for (AssessmentQuestionResponse r : [
      SELECT AssessmentQuestionId, ResponseText, Assessment.Respondent__c
      FROM AssessmentQuestionResponse
      WHERE AssessmentQuestionId IN :setByVersion.keySet()
    WITH SECURITY_ENFORCED
    ]) {
      if (String.isBlank(r.ResponseText))
        continue;
      Id versionId = r.AssessmentQuestionId;
      String choice = r.ResponseText.trim();
      if (!votesByOptionPerPoll.containsKey(versionId)) {
        votesByOptionPerPoll.put(versionId, new Map<String, Integer>());
      }
      Map<String, Integer> bucket = votesByOptionPerPoll.get(versionId);
      bucket.put(
        choice,
        (bucket.containsKey(choice) ? bucket.get(choice) : 0) + 1
      );
      totalVotesPerPoll.put(
        versionId,
        (totalVotesPerPoll.containsKey(versionId)
          ? totalVotesPerPoll.get(versionId)
          : 0) + 1
      );
      if (myAccountId != null && r.Assessment.Respondent__c == myAccountId) {
        myVoteByPoll.put(versionId, choice);
      }
    }

    for (Id versionId : setByVersion.keySet()) {
      Id questionSetId = setByVersion.get(versionId);
      Id feedItemId = feedItemBySet.get(questionSetId);
      if (feedItemId == null)
        continue;
      KenAssessmentSurveyService.QuestionRow row = questionsBySet.get(
        questionSetId
      )[0];
      Datetime endsAt = endsAtBySet.get(questionSetId);

      KenGroupFeedController.PollDTO dto = new KenGroupFeedController.PollDTO();
      dto.pollId = versionId;
      dto.question = row.questionLabel;
      dto.endsAt = endsAt;
      dto.isClosed = endsAt != null && endsAt < Datetime.now();
      Integer total = totalVotesPerPoll.containsKey(versionId)
        ? totalVotesPerPoll.get(versionId)
        : 0;
      dto.totalVotes = total;
      String myResp = myVoteByPoll.get(versionId);
      dto.hasVoted = String.isNotBlank(myResp);
      dto.options = new List<KenGroupFeedController.PollOptionDTO>();

      Map<String, Integer> votesForThisPoll = votesByOptionPerPoll.containsKey(
          versionId
        )
        ? votesByOptionPerPoll.get(versionId)
        : new Map<String, Integer>();
      Integer order = 1;
      List<KenAssessmentSurveyService.ChoiceRow> choices = row.choices == null
        ? new List<KenAssessmentSurveyService.ChoiceRow>()
        : row.choices;
      for (KenAssessmentSurveyService.ChoiceRow choice : choices) {
        String text = choiceText(choice);
        if (String.isBlank(text))
          continue;
        KenGroupFeedController.PollOptionDTO odto = new KenGroupFeedController.PollOptionDTO();
        odto.optionId = text;
        odto.optionText = text;
        odto.order_x = order++;
        Integer castCount = votesForThisPoll.containsKey(text)
          ? votesForThisPoll.get(text)
          : 0;
        odto.voteCount = castCount;
        odto.votePercent = total == 0
          ? 0
          : Math.round(100.0 * castCount / total);
        odto.votedByMe = text == myResp;
        dto.options.add(odto);
      }
      out.put(feedItemId, dto);
    }
    return out;
  }

  private static List<AssessmentQuestionSet> pollSets(Set<Id> feedItemIds) {
    Set<String> feedItemKeys = new Set<String>();
    for (Id feedItemId : feedItemIds) {
      feedItemKeys.add(String.valueOf(feedItemId));
      feedItemKeys.add(String.valueOf(feedItemId).substring(0, 15));
    }
    return [
      SELECT Id, Feed_Item__c, Ends_At__c
      FROM AssessmentQuestionSet
      WHERE Feed_Item__c IN :feedItemKeys
    WITH SECURITY_ENFORCED
    ];
  }

  private static String choiceText(
    KenAssessmentSurveyService.ChoiceRow choice
  ) {
    if (choice == null)
      return null;
    String text = String.isNotBlank(choice.label) ? choice.label : choice.value;
    return String.isBlank(text) ? null : text.trim();
  }

  private static String pollLabel(String value, Integer maxLength) {
    String safe = String.isNotBlank(value) ? value.trim() : 'Group Poll';
    return safe.length() > maxLength ? safe.substring(0, maxLength) : safe;
  }

  private static Id toId(String value) {
    if (String.isBlank(value))
      return null;
    try {
      return Id.valueOf(value);
    } catch (Exception e) {
      return null;
    }
  }

  private static Id currentUserAccountId(Id userId) {
    if (userId == UserInfo.getUserId()) {
      return KenGroupFeedController.resolveCurrentAccountId();
    }
    if (userId == null)
      return null;
    List<User> us = [
      SELECT AccountId, ContactId
      FROM User
      WHERE Id = :userId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (us.isEmpty())
      return null;
    if (us[0].AccountId != null)
      return us[0].AccountId;
    if (us[0].ContactId != null) {
      List<Contact> cs = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :us[0].ContactId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!cs.isEmpty())
        return cs[0].AccountId;
    }
    return null;
  }

  public static String relativeTime(DateTime dt) {
    if (dt == null)
      return '';
    Long diffMs = Datetime.now().getTime() - dt.getTime();
    Long diffMin = diffMs / 60000;
    if (diffMin < 1)
      return 'Just now';
    if (diffMin < 60)
      return diffMin + 'm';
    Long diffHr = diffMin / 60;
    if (diffHr < 24)
      return diffHr + 'h';
    Long diffDay = diffHr / 24;
    if (diffDay < 7)
      return diffDay + 'd';
    return dt.format('d MMM yyyy');
  }
}