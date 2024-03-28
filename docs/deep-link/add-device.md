# Add Device

-   If you have Roam [https://apps.apple.com/us/app/roam/6469834197](https://apps.apple.com/us/app/roam/6469834197) installed, a link to this page will install a new device to your app
-   If it doesn't open immediately, click [here](roamforroku://feedback)

<script>
document.addEventListener('DOMContentLoaded', (event) => {
const queryParams = new URLSearchParams(window.location.search);
const anchorElements = document.querySelectorAll('a');
anchorElements.forEach((anchor) => {
if (anchor.textContent === 'here') {
const queryParamsString = queryParams.toString();
anchor.href = `roamforroku://add-device?${queryParamsString}`;
}
});
});
</script>
