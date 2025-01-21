const Platform = {
	get OS() {
		const userAgent =
			navigator.userAgent || navigator.vendor || window.opera;

		if (/android/i.test(userAgent)) {
			return 'android';
		}

		if (/iPad|iPhone|iPod/.test(userAgent) && !window.MSStream) {
			return 'ios';
		}

		return 'unknown';
	},
};

export default Platform;
