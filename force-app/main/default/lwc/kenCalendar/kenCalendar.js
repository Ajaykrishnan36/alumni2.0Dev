import { LightningElement, track, wire, api } from 'lwc';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import FullCalendarJSFromResource from '@salesforce/resourceUrl/FullCalendarJs';
import { NavigationMixin } from 'lightning/navigation';
import FORM_FACTOR from '@salesforce/client/formFactor';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig'; 
// Static JSON data for calendar events
const SCHEDULED_EVENTS_JSON = [
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2026-02-12T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000w5EAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2026-02-12T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2026-02-13T14:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000w6EAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "14:00 - 14:55",
        "startDateTime": "2026-02-13T14:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2026-02-16T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000w7EAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2026-02-16T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2026-02-25T10:00:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000w8EAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "09:00 - 10:00",
        "startDateTime": "2026-02-25T09:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-08-04T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000w9EAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-08-04T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-08-11T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wAEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-08-11T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-08-18T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wBEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-08-18T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-08-25T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wCEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-08-25T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-09-01T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wDEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-09-01T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-09-08T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wEEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-09-08T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-09-15T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wFEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-09-15T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-09-22T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wGEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-09-22T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-09-29T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wHEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-09-29T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-10-06T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wIEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-10-06T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-10-13T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wJEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-10-13T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-10-20T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wKEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-10-20T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-10-27T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wLEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-10-27T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-11-03T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wMEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-11-03T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-11-10T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wNEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-11-10T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-07-11T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wTEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-07-11T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-07-18T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wUEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-07-18T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-07-25T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wVEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-07-25T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-08-01T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wWEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-08-01T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-08-08T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wXEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-08-08T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-08-15T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wYEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-08-15T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-08-22T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wZEAQ",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-08-22T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-08-29T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000waEAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-08-29T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-09-05T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wbEAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-09-05T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-09-12T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wcEAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-09-12T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-09-19T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wdEAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-09-19T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-09-26T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000weEAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-09-26T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-10-03T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wfEAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-10-03T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-10-10T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wgEAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-10-10T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-10-17T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000whEAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-10-17T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-10-24T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wiEAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-10-24T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-10-31T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wjEAA",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-10-31T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-11-07T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wkEAA",
        "room": "APJ Abdul Kalam 002",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-11-07T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-11-14T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wlEAA",
        "room": "APJ Abdul Kalam 002",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-11-14T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-11-21T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wmEAA",
        "room": "APJ Abdul Kalam 002",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-11-21T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-11-28T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wnEAA",
        "room": "APJ Abdul Kalam 002",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-11-28T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-12-05T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000woEAA",
        "room": "APJ Abdul Kalam 002",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-12-05T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-12-12T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000000wpEAA",
        "room": "APJ Abdul Kalam 002",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-12-12T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-11-07T12:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000001ddEAA",
        "sessionTime": "12:00 - 12:55",
        "startDateTime": "2025-11-07T12:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-07-02T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000002JZEAY",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-07-02T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-12-02T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000002OPEAY",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-12-02T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-12-12T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000002Q1EAI",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-12-12T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-12-13T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000002RdEAI",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-12-13T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-12-08T10:55:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000002TFEAY",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 10:55",
        "startDateTime": "2025-12-08T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "courseName": "Development Activity Program",
        "endDateTime": "2025-11-18T11:00:00",
        "faculty": "Vedanti Test Faculty",
        "id": "a8Hfs00000002WTEAY",
        "room": "APJ Abdul Kalam 001",
        "sessionTime": "10:00 - 11:00",
        "startDateTime": "2025-11-18T10:00:00",
        "title": "DAPG101-UGTERM2"
    },
    {
        "endDateTime": "2025-11-01T11:00:00",
        "id": "aASfs000000054XGAQ",
        "isHybrid": false,
        "isOnline": false,
        "isSession": true,
        "room": "bengaluru",
        "startDateTime": "2025-11-01T10:00:00",
        "title": "Career Connect 25"
    },
    {
        "endDateTime": "2025-11-02T14:00:00",
        "id": "aASfs00000004MzGAI",
        "isHybrid": false,
        "isOnline": true,
        "isSession": true,
        "sessionLink": "https://meet.google.com/ytm-hvoh-svw",
        "startDateTime": "2025-11-02T13:00:00",
        "title": "InfoHub Session 1"
    },
    {
        "endDateTime": "2025-10-31T17:10:00",
        "id": "aASfs00000004mnGAA",
        "isHybrid": false,
        "isOnline": true,
        "isSession": true,
        "sessionLink": "https://hhvhvh",
        "startDateTime": "2025-10-31T16:10:00",
        "title": "hgfxfgcg"
    }
];

export default class KenCalendar extends NavigationMixin(LightningElement) {
  isMobile = false;
  isRendered = false;
  @track activeView = 'agendaDay';
  currentMonth = new Date().getMonth();
  @track currentYear = new Date().getFullYear();
  @track weekRangeText = '';
  @track headerDateText = ''; // New property for header date text
  @track isLoading = false; // Changed to false initially
  @track isCalendarLoading = true; // New property for calendar loading state
  @track events = [];
  @track loadingMessage = 'Loading calendar...';
  slotDurationMinutes = 30;
  daySlotHeight = null;
  highlightedWeekEventElement = null;

  // Schedule a Call modal state
  @track showScheduleModal = false;
  @track scIsOnline = true;
  scMentorMentee = '';
  scTitle = '';
  scDate = '';
  scStartTime = '';
  scEndTime = '';
  scDescription = '';
  scMeetLink = '';

  // Add flags to track loading state
  fullCalendarLoaded = false;
  initRetryAttempted = false;
  calendarInitialized = false;

  connectedCallback() {
    this.isMobile = FORM_FACTOR === 'Small';
    this.loadCustomFonts();
    this.loadScheduledEvents();

    getPrimaryColor().then(color => {
      document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
      document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
      document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
    }).catch(() => {
      // Ignore errors
    });
  }

  loadCustomFonts() {
    // Get the base path properly

    const basePath = window.location.origin;
    const regularFontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Regular.woff2`;
    const boldFontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Light.woff2`;

    const style = document.createElement('style');
    style.innerText = `
      @font-face {
        font-family: 'GeneralSansCustom';
        src: url('${regularFontUrl}') format('woff2');
        font-style: normal;
        font-display: swap;
      }
      @font-face {
        font-family: 'GeneralSansCustomBold';
        src: url('${boldFontUrl}') format('woff2');
        font-style: normal;
        font-display: swap;
      }
    `;
    document.head.appendChild(style);
  }

  loadScheduledEvents() {
    // Use static JSON data instead of API call
    const resultData = SCHEDULED_EVENTS_JSON;
    
    if (resultData && resultData.length > 0) {
      this.events = resultData.map((item, index) => {
        return {
          id: item.id,
          title: item.title || item.courseName,
          start: item.startDateTime,
          end: item.endDateTime,
          faculty: item.faculty,
          facultySalutation: item.facultySalutation,
          room: item.room,
          sessionLink: item.sessionLink,
          courseName: item.courseName,
          isOnline: item.isOnline || false,
          isHybrid: item.isHybrid || false,
          isSession: item.isSession || false,
          //isRegistered: item.isRegistered
        };
      });

      // If calendar is already initialized, update events
      if (this.calendarInitialized) {
        this.updateCalendarEvents();
      }
    } else {
      this.events = [];
    }
  }

  updateCalendarEvents() {
    this.hideWeekEventPopover();
    try {
      const calendarEl = this.template.querySelector('.calendar');
      if (calendarEl && window.$ && window.$.fn.fullCalendar) {
        $(calendarEl).fullCalendar('removeEvents');
        $(calendarEl).fullCalendar('addEventSource', this.events);
        $(calendarEl).fullCalendar('rerenderEvents');
        if (this.activeView === 'agendaDay') {
          this.updateDaySlotMetrics();
          setTimeout(() => this.realignDayViewEvents(), 0);
        }
      }
    } catch (error) {
      console.error('Error updating calendar events:', error);
    }
  }
  // Removed duplicate connectedCallback
  renderedCallback() {
    if (this.isRendered) return;
    this.isRendered = true;
    console.log('Component rendered, loading FullCalendar resources...');
    this.isCalendarLoading = true;
    this.loadingMessage = 'Loading calendar resources...';
    this.loadFullCalendarResources();
  }

  disconnectedCallback() {
    this.cleanupCalendarArtifacts();
  }

  // Fixed resource loading method
  loadFullCalendarResources() {
    console.log('Starting FullCalendar resource loading...');
    this.loadingMessage = 'Loading calendar dependencies...';

    // Load resources in sequence to ensure proper dependency order
    this.loadResourcesSequentially()
      .then(() => {
        console.log('All resources loaded, waiting for dependencies...');
        this.loadingMessage = 'Initializing calendar...';
        this.waitForDependenciesWithTimeout();
      })
      .catch(error => {
        console.error('Resource loading failed:', error);
        this.showErrorMessage('Failed to load calendar resources. Please refresh the page.');
      });
  }

  async loadResourcesSequentially() {
    try {
      // Load jQuery first
      await loadScript(this, FullCalendarJSFromResource + '/fullCalendarV3/lib/jquery.min.js');
      console.log('jQuery loaded');

      // Expose jQuery globally immediately after loading
      if (typeof jQuery !== 'undefined') {
        window.jQuery = window.$ = jQuery;
        console.log('jQuery exposed globally');
      }

      // Load CSS
      await loadStyle(this, FullCalendarJSFromResource + '/fullCalendarV3/fullcalendar.css');
      console.log('FullCalendar CSS loaded');

      // Load Moment.js
      await loadScript(this, FullCalendarJSFromResource + '/fullCalendarV3/lib/moment.min.js');
      console.log('Moment.js loaded');

      // Load FullCalendar
      await loadScript(this, FullCalendarJSFromResource + '/fullCalendarV3/fullcalendar.js');
      console.log('FullCalendar JS loaded');

    } catch (error) {
      console.error('Sequential loading error:', error);
      throw error;
    }
  }

  waitForDependenciesWithTimeout() {
    let attempts = 0;
    const maxAttempts = 30; // Increased to 6 seconds (30 * 200ms)

    const checkDependencies = () => {
      attempts++;
      console.log(`Checking dependencies... attempt ${attempts}/${maxAttempts}`);

      // More thorough dependency check
      const jQueryReady = typeof window.$ !== 'undefined' && window.$ && typeof window.$.fn === 'object';
      const fullCalendarReady = jQueryReady && typeof window.$.fn.fullCalendar === 'function';
      const momentReady = typeof window.moment !== 'undefined' && window.moment;

      console.log('Dependency status:', {
        jQuery: jQueryReady,
        fullCalendar: fullCalendarReady,
        moment: momentReady
      });

      if (fullCalendarReady && momentReady) {
        console.log('✅ All dependencies ready!');
        this.fullCalendarLoaded = true;
        this.loadingMessage = 'Setting up calendar...';
        // Small delay to ensure DOM is ready
        setTimeout(() => {
          this.initializeCalendar();
        }, 100);
      } else if (attempts >= maxAttempts) {
        console.warn('⏰ Dependency check timeout');
        this.showErrorMessage('Calendar failed to load. Please refresh the page.');
      } else {
        setTimeout(checkDependencies, 200);
      }
    };

    checkDependencies();
  }

  cleanupCalendarArtifacts() {
    const hasJquery = typeof window !== 'undefined' && window.$;

    if (hasJquery) {
      this.hideWeekEventPopover();
      window.$('.custom-fc-popover').remove();
      window.$(document).off('click.custom-fc-popover');
    } else {
      const weekPopover = document.querySelector('.week-event-popover');
      if (weekPopover) {
        weekPopover.remove();
      }
      const backdrop = document.querySelector('.calendar-backdrop');
      if (backdrop) {
        backdrop.remove();
      }
      const customPopover = document.querySelector('.custom-fc-popover');
      if (customPopover) {
        customPopover.remove();
      }
    }

    if (hasJquery && window.$.fn && window.$.fn.fullCalendar) {
      const calendarEl = this.template ? this.template.querySelector('.calendar') : null;
      if (calendarEl) {
        window.$(calendarEl).fullCalendar('destroy');
      }
    }

    this.calendarInitialized = false;
    this.highlightedWeekEventElement = null;
  }

  initializeCalendar() {
    if (this.calendarInitialized) {
      console.log('Calendar already initialized');
      return;
    }

    try {
      const calendarEl = this.template.querySelector('.calendar');
      if (!calendarEl) {
        console.error('Calendar element not found - retrying in 500ms...');
        // Retry after a short delay
        setTimeout(() => {
          this.initializeCalendar();
        }, 500);
        return;
      }

      console.log('Calendar element found, initializing FullCalendar...');

      let colorIndex = 0;
      const bgColors = ['rgba(235, 244, 236, 1)', 'rgba(232, 235, 243, 1)', 'rgba(255, 249, 234, 1)'];

      $(calendarEl).fullCalendar({
        timezone: false,
        defaultView: this.activeView,
        editable: false,
        eventLimit: 1,
        eventLimitClick: 'popover',
        allDaySlot: false,
        slotDuration: '00:30:00',
        minTime: '00:00:00',
        maxTime: '24:00:00',
        header: false,
        height: 'auto',
        contentHeight: 'auto',
        aspectRatio: 1.35,
        columnFormat: 'ddd[\n]D MMM',
        events: this.events || [],

        views: {
          agendaDay: {
            eventLimit: false
          },
          agendaWeek: {
            eventLimit: 1,
            eventLimitClick: 'popover'
          },
          month: {
            eventLimit: 2,
            eventLimitClick: 'popover'
          }
        },

        eventRender: (event, element, view) => {
          console.log('Rendering event:', event.title, 'in view:', view.name);
          this.renderEvent(event, element, view, bgColors, colorIndex++);
        },

        viewRender: (view) => {
          this.handleViewRender(view);
        },

        eventAfterAllRender: (view) => {
          if (view.name === 'agendaWeek') {
            this.implementCustomEventLimiting();
            this.reformatWeekHeaders();
          }
          if (view.name === 'agendaDay') {
            this.updateDaySlotMetrics(view);
            this.realignDayViewEvents();
          }
        },

        windowResize: () => {
          this.hideWeekEventPopover();
          setTimeout(() => {
            $(calendarEl).fullCalendar('render');
          }, 150);
        }
      });

      this.calendarInitialized = true;
      const slotDurationOption = $(calendarEl).fullCalendar('option', 'slotDuration');
      if (slotDurationOption) {
        const durationMinutes = moment.duration(slotDurationOption).asMinutes();
        if (!isNaN(durationMinutes) && durationMinutes > 0) {
          this.slotDurationMinutes = durationMinutes;
        }
      }
      this.isCalendarLoading = false; // Set calendar loading to false
      console.log('✅ Calendar initialized successfully!');

      // Update title after initialization
      setTimeout(() => {
        this.updateMonthYearTitle();
      }, 100);

    } catch (error) {
      console.error('Calendar initialization error:', error);
      this.showErrorMessage('Failed to initialize calendar. Please refresh the page.');
    }
  }

  renderEvent(event, element, view, bgColors, colorIndex) {
    const startMoment = moment(event.start);
    const endMoment = moment(event.end);
    const hasValidStart = startMoment.isValid();
    const hasValidEnd = endMoment.isValid();
    const startTime = hasValidStart ? startMoment.format('h:mm A') : '';
    const endTime = hasValidEnd ? endMoment.format('h:mm A') : '';
    const timeDisplay = hasValidStart && hasValidEnd
      ? `${startTime} - ${endTime}`
      : (startTime || endTime || '');
    console.log('Event Data : ', event);
    const isMonthView = view.name === 'month';
    const commonStyles = {
      'border': 'none',
      'border-radius': view.name === 'agendaWeek' ? '8px' : '10px',
      'color': 'black'
    };

    if (view.name === 'agendaDay') {
      // Styles are handled via kenCalendar.css due to jQuery !important rendering issues
    } else if (view.name === 'month') {
      element.css({
        ...commonStyles,
        'background-color': '#F6F8FB',
        'border-left': '10px solid #0070d2 !important',
        'padding': '6px 8px',
        'margin': '0px 10px !important'
      });
    } else if (view.name === 'agendaWeek') {
      element.css({
        ...commonStyles,
        'background-color': '#F6F8FB',
        'padding': '6px 8px',
        'border-radius': '4px',
        'border': 'none'
      });
    }

    // Common HTML template for all views
    const hasSessionLink = !!event.sessionLink;
    const safeSessionLink = hasSessionLink
      ? event.sessionLink
          .replace(/&/g, '&amp;')
          .replace(/"/g, '&quot;')
          .replace(/'/g, '&#39;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
      : '';
    const escapedTitle = this.escapeHtml(event.title || '');
    const escapedCourseName = this.escapeHtml(event.courseName || '');
    const facultyDisplay = this.escapeHtml(event.faculty || '');
    const facultySalutationDisplay = this.escapeHtml(event.facultySalutation || '');
    const facultyDisplayWithSalutation = facultyDisplay || facultySalutationDisplay
      ? `${facultySalutationDisplay ? facultySalutationDisplay + ' ' : ''}${facultyDisplay}`
      : '';
    const roomDisplay = this.escapeHtml(event.room || '');
    const titleContent = `${escapedTitle}${(!event.isSession && escapedCourseName) ? `&nbsp;(${escapedCourseName})` : ''}`;
    const shouldDisableCardClick = isMonthView && hasSessionLink && !event.isSession;
    const cardClasses = ['event-location'];
    if ((hasSessionLink || event.isSession) && !shouldDisableCardClick) {
      cardClasses.push('event-card-click-target');
    }
    if (hasSessionLink) {
      cardClasses.push('event-has-link');
    }
    if (event.isSession) {
      cardClasses.push('event-has-details');
    }
    const cardClassName = cardClasses.join(' ');
    const additionalWeekClass = view.name === 'agendaWeek' ? ' event-week-card' : '';
    const cardStyle = ((hasSessionLink || event.isSession) && !shouldDisableCardClick) ? 'cursor:pointer;' : '';
    const idAttribute = event.isSession ? `data-id="${event.id}"` : '';
    const sessionLinkAttribute = (hasSessionLink && !shouldDisableCardClick) ? `data-session-link="${safeSessionLink}"` : '';
    const showViewMoreButton = view.name === 'agendaWeek' || view.name === 'agendaDay';
    const viewMoreButtonHtml = showViewMoreButton
      ? '<button type="button" class="event-week-view-more" aria-label="View more session details">View more</button>'
      : '';

    const timeBlock = timeDisplay ? `
      <div class="event-detail-time" style="display:flex; align-items:center; gap:6px;">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" style="width:14px; height:14px;">
          <g clip-path="url(#clip0_7498_57677)">
            <path d="M12.8 2.54562H12.2V1.3335H11V2.54562H5V1.3335H3.8V2.54562H3.2C2.54 2.54562 2 3.09107 2 3.75774V13.4547C2 14.1214 2.54 14.6668 3.2 14.6668H12.8C13.46 14.6668 14 14.1214 14 13.4547V3.75774C14 3.09107 13.46 2.54562 12.8 2.54562ZM12.8 13.4547H3.2V6.78804H12.8V13.4547ZM12.8 5.57592H3.2V3.75774H12.8V5.57592Z" fill="#373A45"/>
          </g>
          <defs>
            <clipPath id="clip0_7498_57677">
              <rect width="16" height="16" fill="white"/>
            </clipPath>
          </defs>
        </svg>
        ${timeDisplay}
      </div>
    ` : '';

    const locationBlock = (!event.isOnline || event.isHybrid) && event.room ? `
      <div class="event-detail-location" style="font-weight:600; display:flex; align-items:center; gap:6px;">
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" style="width:14px; height:14px;">
          <path d="M8.00008 8.00016C7.26675 8.00016 6.66675 7.40016 6.66675 6.66683C6.66675 5.9335 7.26675 5.3335 8.00008 5.3335C8.73342 5.3335 9.33342 5.9335 9.33342 6.66683C9.33342 7.40016 8.73342 8.00016 8.00008 8.00016ZM12.0001 6.80016C12.0001 4.38016 10.2334 2.66683 8.00008 2.66683C5.76675 2.66683 4.00008 4.38016 4.00008 6.80016C4.00008 8.36016 5.30008 10.4268 8.00008 12.8935C10.7001 10.4268 12.0001 8.36016 12.0001 6.80016ZM8.00008 1.3335C10.8001 1.3335 13.3334 3.48016 13.3334 6.80016C13.3334 9.0135 11.5534 11.6335 8.00008 14.6668C4.44675 11.6335 2.66675 9.0135 2.66675 6.80016C2.66675 3.48016 5.20008 1.3335 8.00008 1.3335Z" fill="#373A45"/>
        </svg>
        ${roomDisplay}
      </div>
    ` : '';

    const joinLinkBlock = (event.isOnline || event.isHybrid) && hasSessionLink ? `
      <div class="event-detail-link event-location-clickable" style="font-weight:600; display:flex; align-items:center; gap:6px;">
        <a href="${safeSessionLink}" target="_blank" rel="noopener" style="display:flex; align-items:center; gap:6px; color:inherit; text-decoration:none;">
          <span>
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg"> <path fill-rule="evenodd" clip-rule="evenodd" d="M4.41469 6.8511L10.2272 1.03861H7.76049V0H11.4809C11.7677 0 11.9999 0.232687 11.9999 0.519041V4.2394H10.9613V1.77271L5.14879 7.5852L4.41469 6.8511ZM10.8207 6.58972H9.78208V10.2336C9.78208 10.6331 9.45323 10.9615 9.05425 10.9615H1.7664C1.3669 10.9615 1.03857 10.6331 1.03857 10.2336V2.94579C1.03857 2.54628 1.3669 2.21796 1.7664 2.21796H5.41033V1.17935H1.7664C0.793671 1.17935 0 1.97305 0 2.94575V10.2336C0 11.2063 0.794229 12 1.7664 12H9.05425C10.027 12 10.8207 11.2063 10.8207 10.2336L10.8212 6.58967L10.8207 6.58972Z" fill="black"/> </svg>
          </span>
          Click here
        </a>
      </div>
    ` : '';

    const weekPopoverRows = [];
    if (escapedTitle) {
      weekPopoverRows.push(`<div class="week-popover-row"><span class="week-popover-label" style="font-weight:600;">Session name:&nbsp;</span><span>${escapedTitle}</span></div>`);
    }

    if (facultyDisplayWithSalutation) {
      weekPopoverRows.push(`<div class="week-popover-row"><span class="week-popover-label" style="font-weight:600;">Faculty member:&nbsp;</span><span>${facultyDisplayWithSalutation}</span></div>`);
    }

    if (roomDisplay) {
      weekPopoverRows.push(`<div class="week-popover-row"><span class="week-popover-label" style="font-weight:600;">Location :&nbsp;</span><span>${roomDisplay}</span></div>`);
    }

    if (timeDisplay) {
      weekPopoverRows.push(`<div class="week-popover-row"><span class="week-popover-label" style="font-weight:600;">Time :&nbsp;</span><span>${timeDisplay}</span></div>`);
    }

    if (escapedCourseName) {
      weekPopoverRows.push(`<div class="week-popover-row"><span class="week-popover-label" style="font-weight:600;">Course:&nbsp;</span><span>${escapedCourseName}</span></div>`);
    }

    const hasPopoverDetails = weekPopoverRows.length > 0;
    const weekPopoverContent = hasPopoverDetails
      ? `<div class="week-event-popover-content">${weekPopoverRows.join('')}</div>`
      : '<div class="week-popover-empty">No additional details available</div>';
    const fcEventElement = element.closest('.fc-event');
    const eventElementForHighlight = fcEventElement.length ? fcEventElement : element;

    let eventHtml = '';

    if (view.name === 'agendaWeek') {
      const wrapperClasses = `${cardClassName}${additionalWeekClass}`;
      
      const facultyBlock = facultyDisplayWithSalutation
        ? `<div class="event-week-faculty" style="display:flex; align-items:flex-start; gap:4px; color:#666; font-size: 0.75rem; margin-top: 4px; font-weight:500;">
             <svg style="min-width:12px; margin-top:1px;" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
                <circle cx="12" cy="7" r="4"></circle>
             </svg>
             <span style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${facultyDisplayWithSalutation}</span>
           </div>`
        : '';
        
      const locationBlock = roomDisplay
        ? `<div class="event-week-location" style="display:flex; align-items:flex-start; gap:4px; color:#666; font-size: 0.75rem; margin-top: 2px; font-weight:500;">
             <svg style="min-width:12px; margin-top:2px;" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path>
                <circle cx="12" cy="10" r="3"></circle>
             </svg>
             <span style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${roomDisplay}</span>
           </div>`
        : '';
    
      eventHtml = `
        <div class="${wrapperClasses}" style="display:flex; flex-direction:column; width:100%; ${cardStyle}" ${idAttribute} ${sessionLinkAttribute}>
          <div class="event-week-title" style="color:#333; font-weight:700; font-size:0.8rem; line-height:1.2;">${titleContent}</div>
          ${facultyBlock}
          ${locationBlock}
        </div>
      `;
    } else if (view.name === 'agendaDay') {
      const dayCardClasses = `${cardClassName} event-day-card custom-day-view`;
      const facultyBlock = facultyDisplayWithSalutation
        ? `<div class="event-day-faculty custom-day-faculty" style="display:flex; align-items:center; gap:6px; color:#555; font-size: 0.85rem; font-weight:400; margin-top:6px;">
             <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#888" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
                <circle cx="12" cy="7" r="4"></circle>
             </svg>
             <span>${facultyDisplayWithSalutation}</span>
           </div>`
        : '';

      const rightBlockDisplay = [timeDisplay, roomDisplay].filter(Boolean).join(' \u2022 ');

      eventHtml = `
        <div class="${dayCardClasses}" style="display:flex; flex-direction:row; justify-content:space-between; align-items:flex-start; width:100%; ${cardStyle}" ${idAttribute} ${sessionLinkAttribute}>
          <div class="custom-day-left" style="display:flex; flex-direction:column;">
            <div class="event-day-title" style="color:#222; font-weight:700; font-size:0.9rem; line-height:1.3;">${titleContent}</div>
            ${facultyBlock}
          </div>
          <div class="custom-day-right" style="color:#555; font-size:0.82rem; font-weight:400; text-align:right; white-space:nowrap; padding-left:20px;">
            ${rightBlockDisplay}
          </div>
        </div>
      `;
    } else {
      const facultyLabel = facultyDisplayWithSalutation || '';
      const subLabel = escapedCourseName || facultyLabel;
      
      eventHtml = `
        <div class="${cardClassName}" style="padding: 1px 0; ${cardStyle}" ${idAttribute} ${sessionLinkAttribute}>
          <div style="font-weight:600; font-size: 0.75rem; color: #555; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; padding-left: 4px;">
            ${escapedTitle || titleContent}
          </div>
          <div style="font-weight:500; font-size: 0.7rem; color: #777; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; padding-left: 4px;">
            ${subLabel}
          </div>
        </div>
      `;
    }
    

    element.find('.fc-time').remove();
    element.find('.fc-title').html(eventHtml);

    if (hasSessionLink) {
      const linkElement = element.find('.event-detail-link a');
      if (linkElement.length) {
        linkElement.off('click').on('click', (e) => {
          e.stopPropagation();
          const decodedLink = this.decodeHtmlEntities(safeSessionLink);
          if (decodedLink) {
            e.preventDefault();
            window.open(decodedLink, '_blank');
          }
        });
      }
    }

    if (showViewMoreButton) {
      const viewMoreButton = element.find('.event-week-view-more');
      if (viewMoreButton.length) {
        viewMoreButton.data('popoverContent', weekPopoverContent);
        viewMoreButton.off('click').on('click', (e) => {
          e.preventDefault();
          e.stopPropagation();
          const content = $(e.currentTarget).data('popoverContent');
          const fcEventElement = element.closest('.fc-event');
          this.showWeekEventPopover(e.currentTarget, content, fcEventElement);
        });
      }
    }

    if (view.name === 'agendaDay') {
      this.correctDayViewEventPosition(element, startMoment, endMoment);
    }

    if (view.name === 'month') {
      element.off('click.monthPopover').on('click.monthPopover', (evt) => {
        evt.preventDefault();
        evt.stopPropagation();
        this.showWeekEventPopover(element[0], weekPopoverContent, eventElementForHighlight);
      });
    } else {
      element.off('click.monthPopover');
    }

    const cardElement = element.find('.event-card-click-target');
    cardElement.off('click').on('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.hideWeekEventPopover();
      if (isMonthView) {
        this.showWeekEventPopover(e.currentTarget, weekPopoverContent, eventElementForHighlight);
        return;
      }
      const { sessionLink, id } = e.currentTarget.dataset;
      const decodedSessionLink = sessionLink ? this.decodeHtmlEntities(sessionLink) : '';

      if (decodedSessionLink && !isMonthView) {
        window.open(decodedSessionLink, '_blank');
        return;
      }

      if (id) {
        this[NavigationMixin.Navigate]({
          type: 'comm__namedPage',
          attributes: {
            name: 'event_detail__c'
          },
          state: {
            recordId: id
          }
        });
      }
    });
  } 

  handleViewRender(view) {
    this.hideWeekEventPopover();
    $('.fc-popover').remove();
    $('.custom-more-link').remove();
    $(document).off('click.fc-popover');

    this.updateMonthYearTitle();
    this.updateHeaderDateText();
    
    if (view.name === 'agendaWeek') {
      this.updateWeekRange(view.start, view.end);
      this.reformatWeekHeaders();
    }
    if (view.name === 'agendaDay') {
      this.updateDaySlotMetrics(view);
      setTimeout(() => this.realignDayViewEvents(), 0);
    }
  }

  reformatWeekHeaders() {
    try {
      const calendarEl = this.template.querySelector('.calendar');
      if (!calendarEl || !window.$ || !window.moment) return;
      
      const $cal = $(calendarEl);
      // FullCalendar v3 uses th.fc-day-header for column headers
      const $headers = $cal.find('th.fc-day-header');
      
      if (!$headers.length) {
        // Fallback: try broader selector
        const $headersAlt = $cal.find('.fc-head th[data-date]');
        if ($headersAlt.length) {
          $headersAlt.each(function() {
            const dateStr = $(this).attr('data-date');
            if (dateStr) {
              const m = moment(dateStr);
              if (m.isValid()) {
                const dayName = m.format('ddd');
                const dayDate = m.format('D MMM');
                $(this).html('<div style="text-align:center; padding: 6px 0;"><div style="font-weight:700; color:#333; font-size:1.05rem; line-height:1.2;">' + dayName + '</div><div style="font-weight:500; color:#666; font-size:0.85rem; margin-top:4px;">' + dayDate + '</div></div>');
              }
            }
          });
        }
        return;
      }
      
      $headers.each(function() {
        const dateStr = $(this).attr('data-date');
        if (dateStr) {
          const m = moment(dateStr);
          if (m.isValid()) {
            const dayName = m.format('ddd');
            const dayDate = m.format('D MMM');
            $(this).html('<div style="text-align:center; padding: 6px 0;"><div style="font-weight:700; color:#333; font-size:1.05rem; line-height:1.2;">' + dayName + '</div><div style="font-weight:500; color:#666; font-size:0.85rem; margin-top:4px;">' + dayDate + '</div></div>');
          }
        }
      });
    } catch (e) {
      console.error('Error reformatting week headers:', e);
    }
  }

  showErrorMessage(message) {
    this.isCalendarLoading = false; // Set calendar loading to false
    const calendarContainer = this.template.querySelector('.calendar-container');
    if (calendarContainer) {
      calendarContainer.innerHTML = `
        <div style="padding: 20px; text-align: center; border: 1px solid #ddd; border-radius: 8px; background-color: #f8f9fa;">
          <div style="color: #dc3545; font-size: 1.1rem; margin-bottom: 10px;">⚠️ Calendar Loading Error</div>
          <p style="color: #666; margin-bottom: 15px;">${message}</p>
          <button onclick="location.reload()" style="
            background-color: #0070d2; 
            color: white; 
            border: none; 
            padding: 8px 16px; 
            border-radius: 4px; 
            cursor: pointer;
          ">Refresh Page</button>
        </div>
      `;
    }
  }

  // Rest of your methods remain the same...
  datesetup() {
    const input = this.template.querySelector('.date-picker');
    if (input) {
      const isoDate = new Date().toISOString().split('T')[0];
      input.value = isoDate;
    }
  }

  get isMonthView() {
    return this.activeView === 'month';
  }

  get isWeekView() {
    setTimeout(() => {
      this.datesetup();
    }, 150);
    return this.activeView === 'agendaWeek';
  }

  get isDayView() {
    return this.activeView === 'agendaDay';
  }

  get dayButtonClass() {
    return this.activeView === 'agendaDay' ? 'view-btn active' : 'view-btn';
  }

  get weekButtonClass() {
    return this.activeView === 'agendaWeek' ? 'view-btn active' : 'view-btn';
  }

  get monthButtonClass() {
    return this.activeView === 'month' ? 'view-btn active' : 'view-btn';
  }

  get calendarContainerStyle() {
    // Hide calendar content while loading but keep DOM elements present
    return this.isCalendarLoading ? 'opacity: 0.3; pointer-events: none;' : 'opacity: 1; pointer-events: auto;';
  }

  get yearOptions() {
    const years = [];
    const baseYear = new Date().getFullYear();
    for (let i = baseYear - 2; i <= baseYear + 5; i++) {
      years.push({ name: i, selected: i === baseYear });
    }
    return years;
  }

  get monthNames() {
    return [
      { name: 'January', selected: this.currentMonth === 0 },
      { name: 'February', selected: this.currentMonth === 1 },
      { name: 'March', selected: this.currentMonth === 2 },
      { name: 'April', selected: this.currentMonth === 3 },
      { name: 'May', selected: this.currentMonth === 4 },
      { name: 'June', selected: this.currentMonth === 5 },
      { name: 'July', selected: this.currentMonth === 6 },
      { name: 'August', selected: this.currentMonth === 7 },
      { name: 'September', selected: this.currentMonth === 8 },
      { name: 'October', selected: this.currentMonth === 9 },
      { name: 'November', selected: this.currentMonth === 10 },
      { name: 'December', selected: this.currentMonth === 11 }
    ];
  }

  updateMonthYearTitle() {
    try {
      const calendar = $(this.template.querySelector('.calendar'));
      if (!calendar.length || !this.calendarInitialized) return;

      const date = calendar.fullCalendar('getDate');
      if (!date) return;

      const formatted = new Intl.DateTimeFormat('en-US', {
        year: 'numeric',
        month: 'long'
      }).format(date.toDate());

      const titleContainer = this.template.querySelector('.calendar-title');
      if (titleContainer) {
        titleContainer.innerHTML = `<div style="font-weight:600; font-size:18px;">${formatted}</div>`;
      }
    } catch (error) {
      console.error('Error updating title:', error);
    }
  }

  updateWeekRange(start, end) {
    const options = { month: 'short', day: 'numeric' };
    const startStr = new Intl.DateTimeFormat('en-US', options).format(start.toDate());
    const endStr = new Intl.DateTimeFormat('en-US', options).format(end.toDate());
    this.weekRangeText = `${startStr} - ${endStr}, ${start.toDate().getFullYear()}`;
  }

  handleDateChange(event) {
    const date = event.target.value;
    if (date && this.calendarInitialized) {
      $(this.template.querySelector('.calendar')).fullCalendar('gotoDate', date);
      this.updateMonthYearTitle();
      this.updateHeaderDateText();
    }
  }

  handlePrevDate() {
    if (!this.calendarInitialized) return;
    const calendar = $(this.template.querySelector('.calendar'));
    calendar.fullCalendar('prev');
    this.syncDatePickerWithCalendar();
    this.updateMonthYearTitle();
    this.updateHeaderDateText();
  }

  handleNextDate() {
    if (!this.calendarInitialized) return;
    const calendar = $(this.template.querySelector('.calendar'));
    calendar.fullCalendar('next');
    this.syncDatePickerWithCalendar();
    this.updateMonthYearTitle();
    this.updateHeaderDateText();
  }

  syncDatePickerWithCalendar() {
    if (!this.calendarInitialized) return;
    const calendar = $(this.template.querySelector('.calendar'));
    const currentDate = calendar.fullCalendar('getDate');
    const input = this.template.querySelector('.date-picker-hidden-input');
    if (input && currentDate) {
      const isoDate = currentDate.toISOString().split('T')[0];
      input.value = isoDate;
    }
  }

  updateHeaderDateText() {
    if (!this.calendarInitialized) return;
    const calendar = $(this.template.querySelector('.calendar'));
    const date = calendar.fullCalendar('getDate');
    if (!date) return;

    if (this.activeView === 'agendaDay') {
      // e.g. "12 Feb 2026"
      this.headerDateText = new Intl.DateTimeFormat('en-US', { day: 'numeric', month: 'short', year: 'numeric' }).format(date.toDate());
    } else {
      // e.g. "February 2026"
      this.headerDateText = new Intl.DateTimeFormat('en-US', { month: 'long', year: 'numeric' }).format(date.toDate());
    }
  }

  handleScheduleCall() {
    this.showScheduleModal = true;
  }

  handleScheduleCancel() {
    this.showScheduleModal = false;
    this._resetScheduleForm();
  }

  handleModalOverlayClick() {
    this.showScheduleModal = false;
    this._resetScheduleForm();
  }

  handleModalContentClick(event) {
    event.stopPropagation();
  }

  handleScMentorChange(event) {
    this.scMentorMentee = event.target.value;
  }

  handleScTitleChange(event) {
    this.scTitle = event.target.value;
  }

  handleScDateChange(event) {
    this.scDate = event.target.value;
  }

  handleScStartTimeChange(event) {
    this.scStartTime = event.target.value;
  }

  handleScEndTimeChange(event) {
    this.scEndTime = event.target.value;
  }

  handleScDescriptionChange(event) {
    this.scDescription = event.detail.value;
  }

  handleScMeetTypeChange(event) {
    this.scIsOnline = event.target.value === 'online';
  }

  handleScMeetLinkChange(event) {
    this.scMeetLink = event.target.value;
  }

  handleScheduleSend() {
    // TODO: wire up Apex call to save the scheduled call
    console.log('Schedule request:', {
      mentorMentee: this.scMentorMentee,
      title: this.scTitle,
      date: this.scDate,
      startTime: this.scStartTime,
      endTime: this.scEndTime,
      description: this.scDescription,
      isOnline: this.scIsOnline,
      meetLink: this.scMeetLink
    });
    this.showScheduleModal = false;
    this._resetScheduleForm();
  }

  _resetScheduleForm() {
    this.scMentorMentee = '';
    this.scTitle = '';
    this.scDate = '';
    this.scStartTime = '';
    this.scEndTime = '';
    this.scDescription = '';
    this.scMeetLink = '';
    this.scIsOnline = true;
  }

  handleMonthChange(event) {
    this.currentMonth = parseInt(event.target.value, 10);
    this.gotoSelectedMonthYear();
  }

  handleYearChange(event) {
    this.currentYear = parseInt(event.target.value, 10);
    this.gotoSelectedMonthYear();
  }

  gotoSelectedMonthYear() {
    if (!this.calendarInitialized) return;
    const selectedDate = new Date(this.currentYear, this.currentMonth, 1);
    $(this.template.querySelector('.calendar')).fullCalendar('gotoDate', selectedDate);
    this.updateMonthYearTitle();
  }

  switchToDay() {
    if (!this.calendarInitialized) return;
    this.activeView = 'agendaDay';
    const cal = $(this.template.querySelector('.calendar'));
    cal.fullCalendar('changeView', 'agendaDay');
    cal.fullCalendar('today');
    setTimeout(() => {
      cal.fullCalendar('render');
      this.updateDaySlotMetrics();
      this.realignDayViewEvents();
    }, 100);
  }

  switchToWeek() {
    if (!this.calendarInitialized) return;
    this.activeView = 'agendaWeek';
    const cal = $(this.template.querySelector('.calendar'));
    cal.fullCalendar('changeView', 'agendaWeek');
    cal.fullCalendar('today');
    this.updateDaySlotMetrics();
    setTimeout(() => cal.fullCalendar('render'), 100);
  }

  switchToMonth() {
    if (!this.calendarInitialized) return;
    this.activeView = 'month';
    const cal = $(this.template.querySelector('.calendar'));
    cal.fullCalendar('changeView', 'month');
    cal.fullCalendar('today');
    this.updateDaySlotMetrics();
    setTimeout(() => cal.fullCalendar('render'), 100);
  }

  previousWeek() {
    if (!this.calendarInitialized) return;
    const cal = $(this.template.querySelector('.calendar'));
    cal.fullCalendar('prev');
    setTimeout(() => cal.fullCalendar('render'), 100);
  }

  nextWeek() {
    if (!this.calendarInitialized) return;
    const cal = $(this.template.querySelector('.calendar'));
    cal.fullCalendar('next');
    setTimeout(() => cal.fullCalendar('render'), 100);
  }

  decodeHtmlEntities(value) {
    if (!value) {
      return '';
    }
    const textarea = document.createElement('textarea');
    textarea.innerHTML = value;
    return textarea.value;
  }

  escapeHtml(value) {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  hideWeekEventPopover() {
    $('.week-event-popover').remove();
    $('.calendar-backdrop').remove();
    $(document).off('keydown.weekEventPopover');
    if (this.highlightedWeekEventElement && this.highlightedWeekEventElement.length) {
      this.highlightedWeekEventElement.removeClass('highlighted-week-event');
      this.highlightedWeekEventElement = null;
    } else {
      $('.fc-event.highlighted-week-event').removeClass('highlighted-week-event');
    }
  }

  showWeekEventPopover(triggerElement, contentHtml, eventElement) {
    this.hideWeekEventPopover();

    if (!contentHtml) {
      return;
    }

    const $trigger = $(triggerElement);
    if (!$trigger.length) {
      return;
    }

    if (eventElement && eventElement.length) {
      this.highlightWeekEventCard(eventElement);
    }

    const $popover = $(`
      <div class="week-event-popover">
        <div class="week-event-popover-inner" style="position: absolute;
  top: 41%;
  z-index: 9999;
  left: 46%;
  background: white;
  padding: 10px;
  box-shadow: 0px 0px 11px 0px rgba(0, 0, 0, 0.15);
  border-radius: 10px;">
        <div style="display: flex; justify-content: flex-end; margin-bottom:5px;">
                  <button type="button" class="week-event-popover-close" aria-label="Close">&times;</button>
        </div>
          ${contentHtml}
        </div>
      </div>
    `);

    const $backdrop = $('<div class="calendar-backdrop"></div>');
    $('body').append($backdrop).append($popover);

    const closePopover = () => this.hideWeekEventPopover();

    $popover.find('.week-event-popover-close').on('click', closePopover);
    $backdrop.on('click', closePopover);

    setTimeout(() => {
      $popover.find('.week-event-popover-close').focus();
      $(document).on('keydown.weekEventPopover', (event) => {
        if (event.key === 'Escape') {
          this.hideWeekEventPopover();
        }
      });
    }, 0);
  }

  highlightWeekEventCard(element) {
    if (this.highlightedWeekEventElement && this.highlightedWeekEventElement.length && this.highlightedWeekEventElement !== element) {
      this.highlightedWeekEventElement.removeClass('highlighted-week-event');
    }

    if (element && element.length) {
      element.addClass('highlighted-week-event');
      this.highlightedWeekEventElement = element;
    } else {
      this.highlightedWeekEventElement = null;
    }
  }

  updateDaySlotMetrics(viewOverride) {
    const calendarEl = this.template?.querySelector('.calendar');
    let view = viewOverride;

    if (!view && calendarEl && window.$ && window.$.fn.fullCalendar) {
      view = $(calendarEl).fullCalendar('getView');
    }

    if (view && view.type === 'agendaDay' && view.timeGrid) {
      const { slotHeight } = view.timeGrid;
      if (slotHeight && slotHeight > 0) {
        this.daySlotHeight = slotHeight; // Fallback
      }

      const slotDuration = view.opt && view.opt('slotDuration');
      if (slotDuration && window.moment) {
        const durationMinutes = window.moment.duration(slotDuration).asMinutes();
        if (!isNaN(durationMinutes) && durationMinutes > 0) {
          this.slotDurationMinutes = durationMinutes;
        }
      }
    }

    // Force override with visual DOM height because CSS scales the .fc-slats tr row vertically
    const slatRow = this.template.querySelector('.fc-agendaDay-view .fc-slats tr');
    if (slatRow) {
      const fallbackHeight = slatRow.getBoundingClientRect().height;
      if (fallbackHeight) {
        this.daySlotHeight = fallbackHeight;
      }
    }
  }

  getDaySlotHeight() {
    if (!this.daySlotHeight) {
      this.updateDaySlotMetrics();
    }
    return this.daySlotHeight;
  }

  correctDayViewEventPosition(element, startMoment, endMoment) {
    // Removed: was overriding FullCalendar's native positioning with incorrect pixel math
  }

  realignDayViewEvents() {
    // Removed: was calling incorrectDayViewEventPosition which broke time slot alignment
  }

  implementCustomEventLimiting() {
    // Keep your existing implementation
    const eventLimit = 1;
    const $calendar = $(this.template.querySelector('.calendar'));

    $('.fc-time-grid .fc-slats tr').each((slotIndex, slot) => {
      const $slot = $(slot);
      const timeSlot = $slot.find('.fc-time').attr('data-time') || $slot.find('.fc-time').text();

      $('.fc-day-grid .fc-row .fc-content-skeleton tbody tr').each((dayIndex, dayRow) => {
        const $dayCell = $(dayRow).find('td').eq(dayIndex);
        const $events = $dayCell.find('.fc-event');

        if ($events.length > eventLimit) {
          $events.slice(eventLimit).hide();

          if (!$dayCell.find('.custom-more-link').length) {
            const hiddenCount = $events.length - eventLimit;
            const $moreLink = $(`
              <div class="custom-more-link" style="
                background-color: #2b56f6;
                color: white;
                border-radius: 4px;
                padding: 4px 6px;
                font-size: 0.75rem;
                cursor: pointer;
                text-align: center;
                margin-top: 2px;
                font-weight: 500;
                width: 100%;
                box-sizing: border-box;
              ">+${hiddenCount} more event${hiddenCount > 1 ? 's' : ''}</div>
            `);

            $dayCell.append($moreLink);

            $moreLink.on('click', (e) => {
              e.stopPropagation();
              this.showCustomPopover($events, $moreLink, dayIndex);
            });
          }
        }
      });
    });
  }

  showCustomPopover($events, $moreLink, dayIndex) {
    this.hideWeekEventPopover();
    $('.custom-fc-popover').remove();

    let popoverContent = '<div class="fc-popover-content" style="max-height: 300px; overflow-y: auto;">';

    $events.each((index, eventEl) => {
      const $event = $(eventEl);
      const eventObj = $event.data('fc-event');

      if (eventObj) {
        const startTime = moment(eventObj.start).format('h:mm A');
        const endTime = moment(eventObj.end).format('h:mm A');
        const facultyName = this.escapeHtml(eventObj.faculty || '');
        const facultySalutation = this.escapeHtml(eventObj.facultySalutation || '');
        const facultyLabel = (facultyName || facultySalutation)
          ? `${facultySalutation ? facultySalutation + ' ' : ''}${facultyName}`
          : '';
      
        popoverContent += `
          <div style="
            background-color: rgba(232, 235, 243, 1);
            border-left: 4px solid #0070d2;
            border-radius: 6px;
            padding: 8px;
            margin: 4px 0;
            cursor: pointer;
          " class="popover-event">
            <div style="font-weight: 600; font-size: 0.9rem;">
              ${eventObj.title} - ${eventObj.room || ''}
            </div>
            <div style="font-weight: 600; font-size: 0.85rem;">
              ${facultyLabel}
            </div>
            <div style="font-size: 0.8rem; color: #666;">
              🕒 ${startTime} - ${endTime}
            </div>
          </div>
        `;
      }
      
    });

    popoverContent += '</div>';

    const $popover = $(`
      <div class="custom-fc-popover" style="
        position: absolute;
        background: white;
        border: 1px solid #ddd;
        border-radius: 0px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        padding: 12px;
        z-index: 2000;
        max-width: 300px;
        min-width: 250px;
      ">
        <div class="fc-popover-header" style="
          font-weight: 600;
          margin-bottom: 8px;
          padding-bottom: 8px;
          border-bottom: 1px solid #eee;
          font-size: 0.9rem;
        ">${$events.length} events</div>
        ${popoverContent}
        <div class="fc-popover-close" style="
          position: absolute;
          top: 8px;
          right: 10px;
          cursor: pointer;
          font-size: 1.2rem;
          color: #999;
        ">&times;</div>
      </div>
    `);

    const offset = $moreLink.offset();
    $popover.css({
      top: offset.top + $moreLink.outerHeight() + 5,
      left: offset.left
    });

    $('body').append($popover);

    $popover.find('.fc-popover-close').on('click', function () {
      $popover.remove();
    });

    $(document).on('click.custom-fc-popover', function (e) {
      if (!$(e.target).closest('.custom-fc-popover, .custom-more-link').length) {
        $popover.remove();
        $(document).off('click.custom-fc-popover');
      }
    });
  }

  navigateToHome() {
    this[NavigationMixin.Navigate]({
      type: 'comm__namedPage',
      attributes: {
        name: 'Home'
      }
    });
  }

  
}