export const Notice = ( { children, actions } ) => (
	<div data-testid="mock-notice">
		<span>{ children }</span>
		{ actions?.map( ( action, index ) => (
			<button
				key={ index }
				onClick={ action.onClick }
				data-variant={ action.variant }
			>
				{ action.label }
			</button>
		) ) }
	</div>
);
