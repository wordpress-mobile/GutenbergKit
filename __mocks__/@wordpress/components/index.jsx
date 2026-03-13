export const Icon = () => null;

export const Notice = ( { children, onRemove } ) => (
	<div data-testid="mock-notice">
		<span>{ children }</span>
		{ onRemove && (
			<button onClick={ onRemove } data-testid="notice-dismiss">
				Dismiss
			</button>
		) }
	</div>
);
