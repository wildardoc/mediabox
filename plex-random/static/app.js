// Plex Random Player - Frontend JavaScript

document.addEventListener('DOMContentLoaded', function() {
    // Tab switching
    const tabs = document.querySelectorAll('.tab');
    tabs.forEach(tab => {
        tab.addEventListener('click', function() {
            tabs.forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));

            this.classList.add('active');
            document.getElementById(this.dataset.tab + '-tab').classList.add('active');
        });
    });

    // Load filters when library changes
    const movieLibrary = document.getElementById('movie-library');
    const tvLibrary = document.getElementById('tv-library');

    if (movieLibrary) {
        movieLibrary.addEventListener('change', () => loadMovieFilters(movieLibrary.value));
        if (movieLibrary.value) loadMovieFilters(movieLibrary.value);
    }

    if (tvLibrary) {
        tvLibrary.addEventListener('change', () => loadTvFilters(tvLibrary.value));
        if (tvLibrary.value) loadTvFilters(tvLibrary.value);
    }

    // Refresh clients button
    document.getElementById('refresh-clients').addEventListener('click', refreshClients);

    // Play buttons
    document.getElementById('play-movie').addEventListener('click', playRandomMovie);
    document.getElementById('play-episode').addEventListener('click', playRandomEpisode);
});

async function loadMovieFilters(libraryKey) {
    try {
        const [genresRes, ratingsRes] = await Promise.all([
            fetch(`/api/genres/${libraryKey}`),
            fetch(`/api/ratings/${libraryKey}`)
        ]);

        const genres = await genresRes.json();
        const ratings = await ratingsRes.json();

        const genreSelect = document.getElementById('movie-genre');
        genreSelect.innerHTML = '<option value="">Any genre</option>';
        if (genres.success) {
            genres.genres.forEach(g => {
                genreSelect.innerHTML += `<option value="${g}">${g}</option>`;
            });
        }

        const ratingSelect = document.getElementById('movie-rating');
        ratingSelect.innerHTML = '<option value="">Any rating</option>';
        if (ratings.success) {
            ratings.ratings.forEach(r => {
                ratingSelect.innerHTML += `<option value="${r}">${r}</option>`;
            });
        }
    } catch (error) {
        console.error('Error loading movie filters:', error);
    }
}

async function loadTvFilters(libraryKey) {
    try {
        const [showsRes, genresRes, ratingsRes] = await Promise.all([
            fetch(`/api/shows/${libraryKey}`),
            fetch(`/api/genres/${libraryKey}`),
            fetch(`/api/ratings/${libraryKey}`)
        ]);

        const shows = await showsRes.json();
        const genres = await genresRes.json();
        const ratings = await ratingsRes.json();

        const showSelect = document.getElementById('tv-show');
        showSelect.innerHTML = '<option value="">Any show</option>';
        if (shows.success) {
            shows.shows.forEach(s => {
                showSelect.innerHTML += `<option value="${s.key}">${s.title}</option>`;
            });
        }

        const genreSelect = document.getElementById('tv-genre');
        genreSelect.innerHTML = '<option value="">Any genre</option>';
        if (genres.success) {
            genres.genres.forEach(g => {
                genreSelect.innerHTML += `<option value="${g}">${g}</option>`;
            });
        }

        const ratingSelect = document.getElementById('tv-rating');
        ratingSelect.innerHTML = '<option value="">Any rating</option>';
        if (ratings.success) {
            ratings.ratings.forEach(r => {
                ratingSelect.innerHTML += `<option value="${r}">${r}</option>`;
            });
        }
    } catch (error) {
        console.error('Error loading TV filters:', error);
    }
}

async function refreshClients() {
    const select = document.getElementById('client-select');
    const currentValue = select.value;

    try {
        const response = await fetch('/api/clients');
        const data = await response.json();

        if (data.success) {
            select.innerHTML = '<option value="">Select a device...</option>';
            data.clients.forEach(client => {
                const selected = client.identifier === currentValue ? 'selected' : '';
                select.innerHTML += `<option value="${client.identifier}" ${selected}>${client.name} (${client.product})</option>`;
            });
        } else {
            showError('Failed to refresh clients: ' + data.error);
        }
    } catch (error) {
        showError('Error refreshing clients: ' + error.message);
    }
}

async function playRandomMovie() {
    const clientId = document.getElementById('client-select').value;
    if (!clientId) {
        showError('Please select a device first');
        return;
    }

    const button = document.getElementById('play-movie');
    button.disabled = true;
    button.textContent = 'Finding movie...';
    hideMessages();

    try {
        const response = await fetch('/api/play/movie', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                client_id: clientId,
                library_key: document.getElementById('movie-library').value,
                unwatched_only: document.getElementById('movie-unwatched').checked,
                genre: document.getElementById('movie-genre').value,
                content_rating: document.getElementById('movie-rating').value
            })
        });

        const data = await response.json();

        if (data.success) {
            let html = `<p class="title">${data.title} (${data.year})</p>`;
            if (data.fallback && data.plex_url) {
                html += `<p class="fallback-msg">${data.message}</p>`;
                html += `<a href="${data.plex_url}" target="_blank" class="plex-link">Open in Plex</a>`;
            }
            html += `<p class="summary">${data.summary}</p>`;
            showResult(html);
        } else {
            showError(data.error);
        }
    } catch (error) {
        showError('Error: ' + error.message);
    } finally {
        button.disabled = false;
        button.textContent = 'Play Random Movie';
    }
}

async function playRandomEpisode() {
    const clientId = document.getElementById('client-select').value;
    if (!clientId) {
        showError('Please select a device first');
        return;
    }

    const button = document.getElementById('play-episode');
    button.disabled = true;
    button.textContent = 'Finding episode...';
    hideMessages();

    try {
        const response = await fetch('/api/play/episode', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                client_id: clientId,
                library_key: document.getElementById('tv-library').value,
                unwatched_only: document.getElementById('tv-unwatched').checked,
                show_key: document.getElementById('tv-show').value,
                genre: document.getElementById('tv-genre').value,
                content_rating: document.getElementById('tv-rating').value
            })
        });

        const data = await response.json();

        if (data.success) {
            let html = `<p class="title">${data.show}</p>`;
            html += `<p class="meta">Season ${data.season}, Episode ${data.episode}: ${data.title}</p>`;
            if (data.fallback && data.plex_url) {
                html += `<p class="fallback-msg">${data.message}</p>`;
                html += `<a href="${data.plex_url}" target="_blank" class="plex-link">Open in Plex</a>`;
            }
            html += `<p class="summary">${data.summary}</p>`;
            showResult(html);
        } else {
            showError(data.error);
        }
    } catch (error) {
        showError('Error: ' + error.message);
    } finally {
        button.disabled = false;
        button.textContent = 'Play Random Episode';
    }
}

function showResult(html) {
    hideMessages();
    const result = document.getElementById('result');
    document.getElementById('result-content').innerHTML = html;
    result.classList.remove('hidden');
}

function showError(message) {
    hideMessages();
    const error = document.getElementById('error');
    error.textContent = message;
    error.classList.remove('hidden');
}

function hideMessages() {
    document.getElementById('result').classList.add('hidden');
    document.getElementById('error').classList.add('hidden');
}
