public class EDU_Admissions_Swift_Setup_CTRL {
    public void execute() {
        EDU_Admissions_Remote_Site_Settings.create_RemoteSiteSettings();
        EDU_Admissions_Education_Cloud_Setting.enableEducationCloud();
    }

}