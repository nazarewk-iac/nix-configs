polkit.addRule(function (action, subject) {
    polkit.log("action=" + action);
    polkit.log("subject=" + subject);

    if (subject.isInGroup("wheel") && (
        action.id === "org.debian.pcsc-lite.access_pcsc" ||
        action.id === "org.debian.pcsc-lite.access_card"
    )) {
        return polkit.Result.YES;
    }
});
